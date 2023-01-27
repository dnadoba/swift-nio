
public protocol RawEncodable {
    associatedtype Raw: RawWriterProtocol
    var raw: Raw { get }
}

public protocol RawWriterProtocol {
    associatedtype DynamicallySizedRawWriter: DynamicallySizedRawWriterProtocol
    associatedtype FixedSizedRawWriter: FixedSizedRawWriterProtocol
    associatedtype StaticallySizedRawWriter: StaticallySizedRawWriterProtocol
    var dynamicallySizedRawWriter: DynamicallySizedRawWriter { get }
    var fixedSizedWriter: FixedSizedRawWriter? { get }
    var staticallySizedWriter: StaticallySizedRawWriter? { get }
}

public protocol DynamicallySizedRawWriterProtocol {
    var underestimatedSize: Int { get }
    func write(to buffer: inout ByteBuffer)
}

public protocol FixedSizedRawWriterProtocol: DynamicallySizedRawWriterProtocol {
    var fixedSize: Int { get }
    func store(to buffer: UnsafeMutableRawBufferPointer)
}

extension FixedSizedRawWriterProtocol {
    @inlinable public var underestimatedSize: Int { fixedSize }
    @inlinable public func write(to buffer: inout ByteBuffer) {
        let fixedSize = self.fixedSize
        buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: fixedSize) { buffer in
            self.store(to: buffer)
            return fixedSize
        }
    }
}

public protocol StaticallySizedRawWriterProtocol: FixedSizedRawWriterProtocol {
    static var staticRawSize: Int { get }
    func store(to buffer: UnsafeMutableRawBufferPointer)
}

extension StaticallySizedRawWriterProtocol {
    @inlinable public var fixedSize: Int { Self.staticRawSize }
}



@resultBuilder
public struct RawEncodableBuilder {
    public struct Tuple2<First: RawWriterProtocol, Second: RawWriterProtocol>: RawWriterProtocol {
        public struct StaticallySizedRawWriter: StaticallySizedRawWriterProtocol {
            @usableFromInline var first: First.StaticallySizedRawWriter
            @usableFromInline var second: Second.StaticallySizedRawWriter
            
            @inlinable init(first: First.StaticallySizedRawWriter, second: Second.StaticallySizedRawWriter) {
                self.first = first
                self.second = second
            }
            
            @inlinable public static var staticRawSize: Int {
                First.StaticallySizedRawWriter.staticRawSize + Second.StaticallySizedRawWriter.staticRawSize
            }
            @inlinable public func store(to buffer: UnsafeMutableRawBufferPointer) {
                first.store(to: buffer)
                let advancedBuffer = UnsafeMutableRawBufferPointer(fastRebase: buffer.dropFirst(First.StaticallySizedRawWriter.staticRawSize))
                second.store(to: advancedBuffer)
            }
        }
        public struct FixedSizedRawWriter: FixedSizedRawWriterProtocol {
            @usableFromInline var first: First.FixedSizedRawWriter
            @usableFromInline var second: Second.FixedSizedRawWriter
            
            @inlinable init(first: First.FixedSizedRawWriter, second: Second.FixedSizedRawWriter) {
                self.first = first
                self.second = second
            }
            
            @inlinable public var fixedSize: Int {
                first.fixedSize + second.fixedSize
            }
            @inlinable public func store(to buffer: UnsafeMutableRawBufferPointer) {
                first.store(to: buffer)
                let advancedBuffer = UnsafeMutableRawBufferPointer(fastRebase: buffer.dropFirst(first.fixedSize))
                second.store(to: advancedBuffer)
            }
        }
        public struct DynamicallySizedRawWriter: DynamicallySizedRawWriterProtocol {
            @usableFromInline var first: First.DynamicallySizedRawWriter
            @usableFromInline var second: Second.DynamicallySizedRawWriter
            
            @inlinable init(first: First.DynamicallySizedRawWriter, second: Second.DynamicallySizedRawWriter) {
                self.first = first
                self.second = second
            }
            
            @inlinable public var underestimatedSize: Int {
                first.underestimatedSize + second.underestimatedSize
            }
            @inlinable public func write(to buffer: inout ByteBuffer) {
                first.write(to: &buffer)
                second.write(to: &buffer)
            }
        }
        
        @usableFromInline var first: First
        @usableFromInline var second: Second
        
        @inlinable init(first: First, second: Second) {
            self.first = first
            self.second = second
        }
        
        @inlinable public var dynamicallySizedRawWriter: DynamicallySizedRawWriter {
            .init(first: first.dynamicallySizedRawWriter, second: second.dynamicallySizedRawWriter)
        }
        @inlinable public var fixedSizedWriter: FixedSizedRawWriter? {
            guard
                let firstWriter = first.fixedSizedWriter,
                let secondWriter = second.fixedSizedWriter
            else {
                return nil
            }
            // TODO: optimise if one or the other is fixed sized
            return .init(first: firstWriter, second: secondWriter)
        }
        @inlinable public var staticallySizedWriter: StaticallySizedRawWriter? {
            guard
                let firstWriter = first.staticallySizedWriter,
                let secondWriter = second.staticallySizedWriter
            else {
                return nil
            }
            // TODO: optimise if one or the other is statically sized
            return .init(first: firstWriter, second: secondWriter)
        }
    }
}

extension RawEncodableBuilder {
    public struct StaticallySized<Writer: StaticallySizedRawWriterProtocol>: RawWriterProtocol {
        @usableFromInline var writer: Writer
        @inlinable init(writer: Writer) {
            self.writer = writer
        }
        @inlinable public var dynamicallySizedRawWriter: Writer { writer }
        @inlinable public var fixedSizedWriter: Writer? { writer }
        @inlinable public var staticallySizedWriter: Writer? { writer }
    }
}

extension RawEncodableBuilder {
    @inlinable public static func buildExpression<Writer: StaticallySizedRawWriterProtocol>(_ expression: Writer) -> StaticallySized<Writer> {
        StaticallySized(writer: expression)
    }
    @inlinable public static func buildExpression<Encodable: RawEncodable>(_ expression: Encodable) -> Encodable.Raw {
        expression.raw
    }
    //@inline(__always)
    @inlinable public static func buildPartialBlock<First: RawWriterProtocol>(first: First) -> First {
        first
    }
    //@inline(__always)
    @inlinable public static func buildPartialBlock<First: RawWriterProtocol, Second: RawWriterProtocol>(
        accumulated: First,
        next: Second
    ) -> Tuple2<First, Second> {
        Tuple2(first: accumulated, second: next)
    }
}


extension FixedWidthInteger where Self: StaticallySizedRawWriterProtocol {
    @inlinable public static var staticRawSize: Int {
        MemoryLayout<Self>.size
    }
    @inlinable public func store(to buffer: UnsafeMutableRawBufferPointer) {
        buffer.storeBytes(of: self.bigEndian, as: Self.self)
    }
}

extension Int8: StaticallySizedRawWriterProtocol {}
extension Int16: StaticallySizedRawWriterProtocol {}
extension Int32: StaticallySizedRawWriterProtocol {}
extension Int64: StaticallySizedRawWriterProtocol {}
extension UInt8: StaticallySizedRawWriterProtocol {}
extension UInt16: StaticallySizedRawWriterProtocol {}
extension UInt32: StaticallySizedRawWriterProtocol {}
extension UInt64: StaticallySizedRawWriterProtocol {}

extension ByteBuffer {
    @inlinable public mutating func writeRaw<RawWriter: RawWriterProtocol>(
        @RawEncodableBuilder rawBuilder: () -> RawWriter
    ) {
        let raw = rawBuilder()
        if let writer = raw.staticallySizedWriter {
            writer.write(to: &self)
        } else if let writer = raw.fixedSizedWriter {
            writer.write(to: &self)
        } else {
            raw.dynamicallySizedRawWriter.write(to: &self)
        }
    }
}

func foo() {
    var buffer = ByteBuffer()
    buffer.writeRaw {
        UInt32(0)
        UInt32(1)
        UInt32(2)
        UInt32(3)
        UInt32(4)
        UInt32(5)
        UInt32(6)
        UInt32(7)
        UInt32(8)
        UInt32(9)
    }
}
