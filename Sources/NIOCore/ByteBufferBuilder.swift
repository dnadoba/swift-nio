//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

public protocol ThrowingByteBufferSerialisable {
    // hidden private API implemented by primitive types
    // we might want to merge _underestimatedSize and _write into a single method
    // otherwise we need potentially need two passes through all serialisables
    var _underestimatedSize: Int { get }
    func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int
    
    var _size: Int? { get }
    func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int
    
    // public API
    associatedtype Writer: ThrowingByteBufferSerialisable
    @ByteBufferWriteBuilder var writer: Writer { get }
}

extension ThrowingByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        writer._underestimatedSize
    }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        try writer._set(in: &buffer, at: offset)
    }
    
    @inlinable public var _size: Int? { writer._size }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        try writer._setUnsafe(in: buffer)
    }
}

public protocol ByteBufferSerialisable: ThrowingByteBufferSerialisable where Writer: ByteBufferSerialisable {
    func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int
    func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int
}

extension ByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        writer._set(in: &buffer, at: offset)
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        writer._setUnsafe(in: buffer)
    }
}

public protocol StaticallySized {
    static var staticSize: Int { get }
}

extension Never: ByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int { fatalError() }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int { fatalError() }
    @inlinable public var writer: Never { fatalError() }
}

//extension Never: StaticallySized {}

extension ThrowingByteBufferSerialisable where Writer: StaticallySized {
    @inlinable public static var staticSize: Int { Writer.staticSize }
}

public struct ByteBufferSerialisableTuple2<A: ThrowingByteBufferSerialisable, B: ThrowingByteBufferSerialisable> {
    @usableFromInline var a: A
    @usableFromInline var b: B
    @inlinable init(a: A, b: B) {
        self.a = a
        self.b = b
    }
}

extension ByteBufferSerialisableTuple2: ThrowingByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int { a._underestimatedSize + b._underestimatedSize }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        let writtenBytesA = try a._set(in: &buffer, at: offset)
        let writtenBytesB = try b._set(in: &buffer, at: offset + writtenBytesA)
        return writtenBytesA + writtenBytesB
    }
    
    //@inline(__always)
    @inlinable public var _size: Int? {
        guard let aSize = a._size, let bSize = b._size else { return nil }
        return aSize + bSize
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        //guard buffer.count >= a._size! else { fatalError("buffer.count >= _size! \(#function)") }
        let writtenBytesA = try a._setUnsafe(in: buffer)
        
        let advancedPointer = UnsafeMutableRawBufferPointer(fastRebase: buffer.dropFirst(writtenBytesA))
        //guard advancedPointer.count >= b._size! else { fatalError("pointer advancing failed \(#function)") }
        let writtenBytesB = try b._setUnsafe(in: advancedPointer)
        return writtenBytesA &+ writtenBytesB
    }
}

extension ByteBufferSerialisableTuple2: ByteBufferSerialisable where A: ByteBufferSerialisable, B: ByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        let writtenBytesA = a._set(in: &buffer, at: offset)
        let writtenBytesB = b._set(in: &buffer, at: offset + writtenBytesA)
        return writtenBytesA + writtenBytesB
    }
    //@inline(__always)
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        //guard buffer.count >= a._size! else { fatalError("buffer.count >= _size! \(#function)") }
        let writtenBytesA = a._setUnsafe(in: buffer)
        
        let advancedPointer = UnsafeMutableRawBufferPointer(fastRebase: buffer.dropFirst(writtenBytesA))
        //guard advancedPointer.count >= b._size! else { fatalError("pointer advancing failed \(#function)") }
        let writtenBytesB = b._setUnsafe(in: advancedPointer)
        return writtenBytesA &+ writtenBytesB
    }
}

extension ByteBufferSerialisableTuple2: StaticallySized where A: StaticallySized, B: StaticallySized {
    @inlinable public static var staticSize: Int { A.staticSize + B.staticSize }
}


public enum ByteBufferSerialisableEither<A: ThrowingByteBufferSerialisable, B: ThrowingByteBufferSerialisable> {
    case a(A)
    case b(B)
}

extension ByteBufferSerialisableEither: ThrowingByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int {
        switch self {
        case .a(let a): return a._underestimatedSize
        case .b(let b): return b._underestimatedSize
        }
    }
    
    @inlinable public var _size: Int? {
        switch self {
        case .a(let a): return a._size
        case .b(let b): return b._size
        }
    }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        switch self {
        case .a(let a): return try a._set(in: &buffer, at: offset)
        case .b(let b): return try b._set(in: &buffer, at: offset)
        }
    }
    
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        switch self {
        case .a(let a): return try a._setUnsafe(in: buffer)
        case .b(let b): return try b._setUnsafe(in: buffer)
        }
    }
}

extension ByteBufferSerialisableEither: ByteBufferSerialisable where A: ByteBufferSerialisable, B: ByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        switch self {
        case .a(let a): return a._set(in: &buffer, at: offset)
        case .b(let b): return b._set(in: &buffer, at: offset)
        }
    }
    
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        switch self {
        case .a(let a): return a._setUnsafe(in: buffer)
        case .b(let b): return b._setUnsafe(in: buffer)
        }
    }
}

extension Optional: ThrowingByteBufferSerialisable where Wrapped: ThrowingByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int {
        self?._underestimatedSize ?? 0
    }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        try self?._set(in: &buffer, at: offset) ?? 0
    }
    
    @inlinable public var _size: Int? {
        guard let self else { return 0 }
        return self._size
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        try self?._setUnsafe(in: buffer) ?? 0
    }
}

extension Optional: ByteBufferSerialisable where Wrapped: ByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        self?._set(in: &buffer, at: offset) ?? 0
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        self?._setUnsafe(in: buffer) ?? 0
    }
}

public struct VoidSerialisable: ByteBufferSerialisable, StaticallySized {
    @inlinable public static var staticSize: Int { 0 }
    @inlinable init() {}
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int { 0}
    @inlinable public var _size: Int? { 0 }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int { 0 }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int { 0 }
}

@resultBuilder public enum ByteBufferWriteBuilder {
    public static func buildBlock() -> VoidSerialisable {
        VoidSerialisable()
    }

    @inlinable public static func buildPartialBlock<First: ThrowingByteBufferSerialisable>(first: First) -> First {
        first
    }
    @inlinable public static func buildPartialBlock(first: Void) -> VoidSerialisable {
        VoidSerialisable()
    }
    //@inline(__always)
    @inlinable public static func buildPartialBlock<First: ThrowingByteBufferSerialisable, Second: ThrowingByteBufferSerialisable>(
        accumulated: First,
        next: Second
    ) -> ByteBufferSerialisableTuple2<First, Second> {
        ByteBufferSerialisableTuple2(a: accumulated, b: next)
    }

    @inlinable public static func buildEither<First: ThrowingByteBufferSerialisable, Second: ThrowingByteBufferSerialisable>(
        first component: First
    ) -> ByteBufferSerialisableEither<First, Second> {
        ByteBufferSerialisableEither<First, Second>.a(component)
    }
    @inlinable public static func buildEither<First: ThrowingByteBufferSerialisable, Second: ThrowingByteBufferSerialisable>(
        second component: Second
    ) -> ByteBufferSerialisableEither<First, Second> {
        ByteBufferSerialisableEither<First, Second>.b(component)
    }
    
    @inlinable public static func buildOptional<Component: ThrowingByteBufferSerialisable>(_ component: Component?) -> Component? {
        component
    }
    @inlinable public static func buildLimitedAvailability<Component>(component: Component) -> Component {
        component
    }
    // TODO: should we add buildArray as well? use case?
}

extension ByteBuffer {
    @inlinable public init(@ByteBufferWriteBuilder builder: () -> some ThrowingByteBufferSerialisable) throws {
        let serialisable = builder()
        
        if let size = serialisable._size {
            var buffer = ByteBuffer(allocator: .init(), startingCapacity: size)
            try buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: size) { buffer in
                let writtenBytes = try serialisable._setUnsafe(in: buffer)

                precondition(writtenBytes == size, "promised to write \(size) bytes but actually \(writtenBytes) bytes were written")
                return writtenBytes
            }
            self = buffer
        } else {
            var buffer = ByteBuffer(allocator: .init(), startingCapacity: serialisable._underestimatedSize)
            let writtenBytes = try serialisable._set(in: &buffer, at: 0)
            buffer.moveWriterIndex(to: writtenBytes)
            self = buffer
        }
    }
    
    @inlinable public init(@ByteBufferWriteBuilder builder: () throws -> some ByteBufferSerialisable) throws {
        let serialisable = try builder()
        
        if let size = serialisable._size {
            var buffer = ByteBuffer(allocator: .init(), startingCapacity: size)
            buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: size) { buffer in
                let writtenBytes = serialisable._setUnsafe(in: buffer)

                precondition(writtenBytes == size, "promised to write \(size) bytes but actually \(writtenBytes) bytes were written")
                return writtenBytes
            }
            self = buffer
        } else {
            var buffer = ByteBuffer(allocator: .init(), startingCapacity: serialisable._underestimatedSize)
            let writtenBytes = serialisable._set(in: &buffer, at: 0)
            buffer.moveWriterIndex(to: writtenBytes)
            self = buffer
        }
    }
    
    @inlinable public init(@ByteBufferWriteBuilder builder: () -> some ByteBufferSerialisable) {
        let serialisable = builder()
        
        if let size = serialisable._size {
            var buffer = ByteBuffer(allocator: .init(), startingCapacity: size)
            buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: size) { buffer in
                let writtenBytes = serialisable._setUnsafe(in: buffer)

                precondition(writtenBytes == size, "promised to write \(size) bytes but actually \(writtenBytes) bytes were written")
                return writtenBytes
            }
            self = buffer
        } else {
            var buffer = ByteBuffer(allocator: .init(), startingCapacity: serialisable._underestimatedSize)
            let writtenBytes = serialisable._set(in: &buffer, at: 0)
            buffer.moveWriterIndex(to: writtenBytes)
            self = buffer
        }
    }
}

extension ByteBuffer {
    @discardableResult
    @inlinable public mutating func write(
        @ByteBufferWriteBuilder builder: () throws -> some ThrowingByteBufferSerialisable
    ) throws -> Int {
        let serialisable = try builder()
        
        if let size = serialisable._size {
            return try self.writeWithUnsafeMutableBytes(minimumWritableBytes: size) { buffer in
                let writtenBytes = try serialisable._setUnsafe(in: buffer)

                precondition(writtenBytes == size, "promised to write \(size) bytes but actually \(writtenBytes) bytes were written")
                return writtenBytes
            }
        } else {
            self.reserveCapacity(minimumWritableBytes: serialisable._underestimatedSize)
            let writtenBytes = try serialisable._set(in: &self, at: self.writerIndex)
            self.moveWriterIndex(forwardBy: writtenBytes)
            return writtenBytes
        }
    }
    
    @discardableResult
    //@inline(__always)
    @inlinable public mutating func write(
        @ByteBufferWriteBuilder builder: () throws -> some ByteBufferSerialisable
    ) rethrows -> Int {
        let serialisable = try builder()
        
        if let size = serialisable._size {
            return self.writeWithUnsafeMutableBytes(minimumWritableBytes: size) { buffer in
                let writtenBytes = serialisable._setUnsafe(in: buffer)

                precondition(writtenBytes == size, "promised to write \(size) bytes but actually \(writtenBytes) bytes were written")
                return writtenBytes
            }
        } else {
            self.reserveCapacity(minimumWritableBytes: serialisable._underestimatedSize)
            let writtenBytes = serialisable._set(in: &self, at: self.writerIndex)
            self.moveWriterIndex(forwardBy: writtenBytes)
            return writtenBytes
        }
    }
}



extension FixedWidthInteger where Self: ByteBufferSerialisable & StaticallySized {
    @inlinable public var writer: Never { fatalError() }
    
    @inlinable public static var staticSize: Int { MemoryLayout<Self>.size }
    @inlinable public var _underestimatedSize: Int { MemoryLayout<Self>.size }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.setInteger(self, at: offset)
    }
    
    //@inline(__always)
    @inlinable public var _size: Int? { MemoryLayout<Self>.size }
    //@inline(__always)
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        buffer.storeBytes(of: self.bigEndian, as: Self.self)
        return MemoryLayout<Self>.size
    }
}

extension Int8: ByteBufferSerialisable, StaticallySized {}
extension Int16: ByteBufferSerialisable, StaticallySized {}
extension Int32: ByteBufferSerialisable, StaticallySized {}
extension Int64: ByteBufferSerialisable, StaticallySized {}
extension UInt8: ByteBufferSerialisable, StaticallySized {}
extension UInt16: ByteBufferSerialisable, StaticallySized {}
extension UInt32: ByteBufferSerialisable, StaticallySized {}
extension UInt64: ByteBufferSerialisable, StaticallySized {}

extension String: ByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        self.utf8.count
    }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.setString(self, at: offset)
    }
    
    @inlinable public var _size: Int? { nil }
    
    @inlinable public var writer: Never { fatalError() }
}

extension Substring: ByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        self.utf8.count
    }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.setSubstring(self, at: offset)
    }
    
    @inlinable public var _size: Int? { nil }
    @inlinable public var writer: Never { fatalError() }
}

extension ByteBuffer: ByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        self.readableBytes
    }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.setBuffer(self, at: offset)
    }
    @inlinable public var _size: Int? { nil }
    @inlinable public var writer: Never { fatalError() }
}

public struct IntegerLengthPrefixed<LengthPrefixInteger: FixedWidthInteger, Message: ThrowingByteBufferSerialisable>: ThrowingByteBufferSerialisable {
    @usableFromInline var message: Message

    init(
        lengthPrefixInteger: LengthPrefixInteger.Type = LengthPrefixInteger.self,
        @ByteBufferWriteBuilder messageBuilder: () -> Message
    ) {
        self.message = messageBuilder()
    }

    @inlinable public var _underestimatedSize: Int {
        MemoryLayout<LengthPrefixInteger>.size + message._underestimatedSize
    }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        let lengthPrefixOffset = offset
        let messageOffset = offset + MemoryLayout<LengthPrefixInteger>.size

        let messageLength = try message._set(in: &buffer, at: messageOffset)

        guard let lengthPrefix = LengthPrefixInteger(exactly: messageLength) else {
            throw ByteBuffer.LengthPrefixError.messageLengthDoesNotFitExactlyIntoRequiredIntegerFormat
        }

        buffer.setInteger(lengthPrefix, at: lengthPrefixOffset)

        return MemoryLayout<LengthPrefixInteger>.size + messageLength
    }

    @inlinable public var _size: Int? { nil }
    @inlinable public var writer: Never { fatalError() }
}

public struct LengthPrefixed<Header: ThrowingByteBufferSerialisable & StaticallySized, Body: ThrowingByteBufferSerialisable> {
    @usableFromInline var makeHeader: @Sendable (Int) throws -> Header
    @usableFromInline var body: Body
    
    @inlinable public init(
        @ByteBufferWriteBuilder headerWithBodySize: @escaping @Sendable (Int) throws -> Header,
        @ByteBufferWriteBuilder body: () -> Body
    ) {
        self.makeHeader = headerWithBodySize
        self.body = body()
    }
}

extension LengthPrefixed: ThrowingByteBufferSerialisable {
    public var writer: Never { fatalError() }
    
    @inlinable public var _underestimatedSize: Int {
        Header.staticSize + body._underestimatedSize
    }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        let headerOffset = offset
        let headerSize = Header.staticSize
        let bodyOffset = headerOffset + headerSize
        let bodySize = try body._set(in: &buffer, at: bodyOffset)
        let headerBytesWritten = try makeHeader(bodySize)._set(in: &buffer, at: headerOffset)
        assert(headerBytesWritten == headerSize)
        return headerSize + bodySize
    }
    
    @inlinable public var _size: Int? {
        guard let bodySize = body._size else {
            return nil
        }
        return Header.staticSize + bodySize
    }
    
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        let headerBuffer = UnsafeMutableRawBufferPointer(fastRebase: buffer[..<Header.staticSize])
        let bodyBuffer = UnsafeMutableRawBufferPointer(fastRebase: buffer[Header.staticSize...])
        let bodySize = try body._setUnsafe(in: bodyBuffer)
        let headerSize = try makeHeader(bodySize)._setUnsafe(in: headerBuffer)
        assert(headerSize == Header.staticSize)
        return headerSize + bodySize
    }
}

extension LengthPrefixed: StaticallySized where Header: StaticallySized, Body: StaticallySized {
    public static var staticSize: Int { Header.staticSize + Body.staticSize }
}

extension LengthPrefixed where Header: FixedWidthInteger & ThrowingByteBufferSerialisable {
    @inlinable public init(
        integerType: Header.Type,
        @ByteBufferWriteBuilder body: () -> Body
    ) {
        self.init(headerWithBodySize: { messageLength in
            try Header(messageLength: messageLength)
        }, body: body)
    }
}

extension FixedWidthInteger {
    @inlinable init(messageLength: some BinaryInteger) throws {
        guard let lengthPrefix = Self(exactly: messageLength) else {
            throw ByteBuffer.LengthPrefixError.messageLengthDoesNotFitExactlyIntoRequiredIntegerFormat
        }
        self = lengthPrefix
    }
}


public struct ByteBufferWriter: ByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    
    @usableFromInline var underestimatedSize: Int
    @usableFromInline var write: @Sendable (inout ByteBuffer) -> ()
    @inlinable public init(underestimatedSize: Int = 0, write: @escaping @Sendable (inout ByteBuffer) -> Void) {
        self.underestimatedSize = underestimatedSize
        self.write = write
    }
    
    @inlinable public var _underestimatedSize: Int { 0 }
    @inlinable public var _size: Int? { nil }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.moveWriterIndex(to: offset)
        write(&buffer)
        let bytesWritten = buffer.writerIndex - offset
        assert(bytesWritten >= 0)
        return bytesWritten
    }
}
