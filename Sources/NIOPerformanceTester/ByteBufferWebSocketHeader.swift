
import NIOCore

private let maxOneByteSize = 125
private let maxTwoByteSize = Int(UInt16.max)
#if arch(arm) || arch(i386)
// on 32-bit platforms we can't put a whole UInt32 in an Int
private let maxNIOFrameSize = Int(UInt32.max / 2)
#else
// on 64-bit platforms this works just fine
private let maxNIOFrameSize = Int(UInt32.max)
#endif

private extension UInt8 {
    func isAnyBitSetInMask(_ mask: UInt8) -> Bool {
        return self & mask != 0
    }

    mutating func changingBitsInMask(_ mask: UInt8, to: Bool) {
        if to {
            self |= mask
        } else {
            self &= ~mask
        }
    }
}

/// A single 4-byte websocket masking key.
///
/// WebSockets uses a masking key to prevent malicious users from injecting
/// predictable binary sequences into websocket data streams. This structure provides
/// a more convenient method of interacting with a masking key than simply by passing
/// around a four-tuple.
public struct WebSocketMaskingKey: Sendable {
    @usableFromInline internal let _key: (UInt8, UInt8, UInt8, UInt8)

    public init?<T: Collection>(_ buffer: T) where T.Element == UInt8 {
        guard buffer.count == 4 else {
            return nil
        }

        self._key = (buffer[buffer.startIndex],
                     buffer[buffer.index(buffer.startIndex, offsetBy: 1)],
                     buffer[buffer.index(buffer.startIndex, offsetBy: 2)],
                     buffer[buffer.index(buffer.startIndex, offsetBy: 3)])
    }

    /// Creates a websocket masking key from the network-encoded
    /// representation.
    ///
    /// - parameters:
    ///     - integer: The encoded network representation of the
    ///         masking key.
    @usableFromInline
    internal init(networkRepresentation integer: UInt32) {
        self._key = (UInt8((integer & 0xFF000000) >> 24),
                     UInt8((integer & 0x00FF0000) >> 16),
                     UInt8((integer & 0x0000FF00) >> 8),
                     UInt8(integer & 0x000000FF))
    }
}

extension WebSocketMaskingKey: FixedSized, StaticallySized {
    public var writer: some FixedSized & StaticallySized {
        _key.0
        _key.1
        _key.2
        _key.3
    }
}

extension WebSocketMaskingKey: ExpressibleByArrayLiteral {
    public typealias ArrayLiteralElement = UInt8

    public init(arrayLiteral elements: UInt8...) {
        precondition(elements.count == 4, "WebSocketMaskingKeys must be exactly 4 bytes long")
        self.init(elements)! // length precondition above
    }
}

extension WebSocketMaskingKey {
    /// Returns a random masking key, using the given generator as a source for randomness.
    /// - Parameter generator: The random number generator to use when creating the
    ///     new random masking key.
    /// - Returns: A random masking key
    @inlinable
    public static func random<Generator>(
        using generator: inout Generator
    ) -> WebSocketMaskingKey where Generator: RandomNumberGenerator {
        return WebSocketMaskingKey(networkRepresentation: .random(in: UInt32.min...UInt32.max, using: &generator))
    }
    
    /// Returns a random masking key, using the `SystemRandomNumberGenerator` as a source for randomness.
    /// - Returns: A random masking key
    @inlinable
    public static func random() -> WebSocketMaskingKey {
        var generator = SystemRandomNumberGenerator()
        return .random(using: &generator)
    }
}

extension WebSocketMaskingKey: Equatable {
    public static func ==(lhs: WebSocketMaskingKey, rhs: WebSocketMaskingKey) -> Bool {
        return lhs._key == rhs._key
    }
}

extension WebSocketMaskingKey: Collection {
    public typealias Element = UInt8
    public typealias Index = Int

    public var startIndex: Int { return 0 }
    public var endIndex: Int { return 4 }

    public func index(after: Int) -> Int {
        return after + 1
    }

    public subscript(index: Int) -> UInt8 {
        switch index {
        case 0:
            return self._key.0
        case 1:
            return self._key.1
        case 2:
            return self._key.2
        case 3:
            return self._key.3
        default:
            fatalError("Invalid index on WebSocketMaskingKey: \(index)")
        }
    }

    @inlinable
    public func withContiguousStorageIfAvailable<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R? {
        return try withUnsafeBytes(of: self._key) { ptr in
            // this is boilerplate necessary to convert from UnsafeRawBufferPointer to UnsafeBufferPointer<UInt8>
            // we know ptr is bound since we defined self._key as let
            let typedPointer = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self)
            let typedBufferPointer = UnsafeBufferPointer(start: typedPointer, count: ptr.count)
            return try body(typedBufferPointer)
        }
    }
}



extension ByteBuffer {
    fileprivate mutating func prependFrameHeaderIfPossible(_ frameHeader: FrameHeader) -> Bool {
        let written: Int? = self.modifyIfUniquelyOwned { buffer in
            let startIndex = buffer.readerIndex - frameHeader.requiredBytes

            guard startIndex >= 0 else {
                return 0
            }

            let written = buffer.setFrameHeader(frameHeader, at: startIndex)
            buffer.moveReaderIndex(to: startIndex)
            return written
        }

        switch written {
        case .none, .some(0):
            return false
        case .some(let x):
            assert(x == frameHeader.requiredBytes)
            return true
        }
    }

    @discardableResult
    fileprivate mutating func writeFrameHeader(_ frameHeader: FrameHeader) -> Int {
        let written = self.setFrameHeader(frameHeader, at: self.writerIndex)
        self.moveWriterIndex(forwardBy: written)
        return written
    }

    @discardableResult
    private mutating func setFrameHeader(_ frameHeader: FrameHeader, at index: Int) -> Int {
        var writeIndex = index

        // Calculate some information about the mask.
        let maskBitMask: UInt8 = frameHeader.maskKey != nil ? 0x80 : 0x00
        let frameLength = frameHeader.length

        // Time to add the extra bytes. To avoid checking this twice, we also start writing stuff out here.
        switch frameLength {
        case 0...maxOneByteSize:
            writeIndex += self.setInteger(frameHeader.firstByte, at: writeIndex)
            writeIndex += self.setInteger(UInt8(frameLength) | maskBitMask, at: writeIndex)
        case (maxOneByteSize + 1)...maxTwoByteSize:
            writeIndex += self.setInteger(frameHeader.firstByte, at: writeIndex)
            writeIndex += self.setInteger(UInt8(126) | maskBitMask, at: writeIndex)
            writeIndex += self.setInteger(UInt16(frameLength), at: writeIndex)
        case (maxTwoByteSize + 1)...maxNIOFrameSize:
            writeIndex += self.setInteger(frameHeader.firstByte, at: writeIndex)
            writeIndex += self.setInteger(UInt8(127) | maskBitMask, at: writeIndex)
            writeIndex += self.setInteger(UInt64(frameLength), at: writeIndex)
        default:
            fatalError("NIO cannot serialize frames longer than \(maxNIOFrameSize)")
        }

        if let maskKey = frameHeader.maskKey {
            writeIndex += self.setBytes(maskKey, at: writeIndex)
        }

        return writeIndex - index
    }
}

extension FrameHeader: FixedSized {
    var writer: some FixedSized {
        // Calculate some information about the mask.
        let maskBitMask: UInt8 = self.maskKey != nil ? 0x80 : 0x00
        let frameLength = self.length

        self.firstByte
        
        // Time to add the extra bytes. To avoid checking this twice, we also start writing stuff out here.
        switch frameLength {
        case 0...maxOneByteSize:
            UInt8(frameLength) | maskBitMask
        case (maxOneByteSize + 1)...maxTwoByteSize:
            UInt8(126) | maskBitMask
            UInt16(frameLength)
        case (maxTwoByteSize + 1)...maxNIOFrameSize:
            UInt8(127) | maskBitMask
            UInt64(frameLength)
        default:
            fatalError("NIO cannot serialize frames longer than \(maxNIOFrameSize)")
        }

        self.maskKey
    }
}




/// A helper object that holds only a websocket frame header. Used to avoid accidentally CoWing on some paths.
fileprivate struct FrameHeader {
    var length: Int
    var maskKey: WebSocketMaskingKey?
    var firstByte: UInt8 = 0

    var requiredBytes: Int {
        var size = 2  // First byte and initial length byte

        switch self.length {
        case 0...maxOneByteSize:
            // Only requires the initial length byte
            break
        case (maxOneByteSize + 1)...maxTwoByteSize:
            // Requires an extra UInt16
            size += MemoryLayout<UInt16>.size
        case (maxTwoByteSize + 1)...maxNIOFrameSize:
            size += MemoryLayout<UInt64>.size
        default:
            fatalError("NIO cannot serialize frames longer than \(maxNIOFrameSize)")
        }

        if maskKey != nil {
            size += 4  // Masking key
        }


        return size
    }
}

// 30% faster

final class ByteBufferWriteWebSocketHeaderHandWritten: Benchmark {
    private let iterations: Int
    private var buffer: ByteBuffer = .init()
    private let header = FrameHeader(length: 10, maskKey: .random(), firstByte: 4)

    init(iterations: Int) {
        self.iterations = iterations
    }

    func setUp() throws {}

    func tearDown() {
        let expectedBuffer = ByteBuffer { header }
        
        precondition(expectedBuffer == buffer)
    }

    func run() throws -> Int {
        var bytesWritten = 0
        
        for _ in 0..<self.iterations {
            buffer = ByteBuffer()
            buffer.reserveCapacity(header.requiredBytes)
            buffer.writeFrameHeader(header)
            bytesWritten += buffer.readerIndex
        }
        
        return bytesWritten
    }
}

final class ByteBufferWriteWebSocketHeaderResultBuilder: Benchmark {
    private let iterations: Int
    private var buffer: ByteBuffer = .init()
    private let header = FrameHeader(length: 10, maskKey: .random(), firstByte: 4)

    init(iterations: Int) {
        self.iterations = iterations
    }

    func setUp() throws {}

    func tearDown() {
        var expectedBuffer = ByteBuffer()
        expectedBuffer.writeFrameHeader(header)
        precondition(expectedBuffer == buffer)
    }

    func run() throws -> Int {
        var bytesWritten = 0
        
        for _ in 0..<self.iterations {
            buffer = ByteBuffer()
            buffer.write { header }
            bytesWritten += buffer.readerIndex
        }
        
        return bytesWritten
    }
}
