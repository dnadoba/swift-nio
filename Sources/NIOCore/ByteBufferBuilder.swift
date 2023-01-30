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

// MARK: Dynamically Sized ByteBuffer Serialisable

public protocol ThrowingByteBufferSerialisable {
    // hidden private API implemented by primitive types
    // we might want to merge _underestimatedSize and _write into a single method
    // otherwise we need potentially need two passes through all serialisables
    static var _minStaticSize: Int { get }
    static var _maxStaticSize: Int? { get }
    var _underestimatedSize: Int { get }
    func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int
    func _write(to buffer: inout ByteBuffer) throws -> Int
    
    // public API
    associatedtype Writer: ThrowingByteBufferSerialisable
    @ByteBufferWriteBuilder var writer: Writer { get }
}

public protocol ByteBufferSerialisable: ThrowingByteBufferSerialisable where Writer: ByteBufferSerialisable {
    func _write(to buffer: inout ByteBuffer) -> Int
    func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int
}

// MARK: Fixed Sized ByteBuffer Serialisable

public protocol ThrowingFixedSized: ThrowingByteBufferSerialisable where Writer: ThrowingFixedSized {
    var _size: Int { get }
    func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int
}

public protocol FixedSized: ThrowingFixedSized, ByteBufferSerialisable where Writer: FixedSized {
    func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int
}

// MARK: Statically Sized ByteBuffer Serialisable

public protocol StaticallySized {
    static var staticSize: Int { get }
}

// MARK: Default implementations

extension ThrowingByteBufferSerialisable {
    @inlinable public static var _minStaticSize: Int { Writer._minStaticSize }
    @inlinable public static var _maxStaticSize: Int? { Writer._maxStaticSize }
    @inlinable public var _underestimatedSize: Int {
        writer._underestimatedSize
    }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        try writer._set(in: &buffer, at: offset)
    }
}

extension ByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        writer._set(in: &buffer, at: offset)
    }
}

extension ThrowingFixedSized {
    @inlinable public var _underestimatedSize: Int { _size }
    @inlinable public var _size: Int { writer._size }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        let size = self._size
        buffer.moveWriterIndex(to: offset)
        return try buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: size) { buffer in
            let writtenBytes = try self._setUnsafe(in: buffer)

            precondition(writtenBytes == size, "promised to write \(size) bytes but actually \(writtenBytes) bytes were written")
            return writtenBytes
        }
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        try writer._setUnsafe(in: buffer)
    }
}

extension FixedSized {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        let size = self._size
        buffer.moveWriterIndex(to: offset)
        return buffer.writeWithUnsafeMutableBytes(minimumWritableBytes: size) { buffer in
            let writtenBytes = self._setUnsafe(in: buffer)

            precondition(writtenBytes == size, "promised to write \(size) bytes but actually \(writtenBytes) bytes were written")
            return writtenBytes
        }
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        writer._setUnsafe(in: buffer)
    }
}

extension ThrowingByteBufferSerialisable where Writer: StaticallySized {
    @inlinable public static var staticSize: Int { Writer.staticSize }
}

// MARK: write implementation

extension ThrowingByteBufferSerialisable {
    @inlinable public func _write(to buffer: inout ByteBuffer) throws -> Int {
        buffer.reserveCapacity(minimumWritableBytes: self._underestimatedSize)
        let initialWriterIndex = buffer.writerIndex
        let writtenBytes = try self._set(in: &buffer, at: initialWriterIndex)
        buffer.moveWriterIndex(to: initialWriterIndex + writtenBytes)
        return writtenBytes
    }
}

extension ByteBufferSerialisable {
    @inlinable public func _write(to buffer: inout ByteBuffer) -> Int {
        buffer.reserveCapacity(minimumWritableBytes: self._underestimatedSize)
        let initialWriterIndex = buffer.writerIndex
        let writtenBytes = self._set(in: &buffer, at: initialWriterIndex)
        buffer.moveWriterIndex(to: initialWriterIndex + writtenBytes)
        return writtenBytes
    }
}


extension StaticallySized where Self: ThrowingByteBufferSerialisable {
    @inlinable public static var _minStaticSize: Int { Self.staticSize }
    @inlinable public static var _maxStaticSize: Int? { Self.staticSize }
}

// MARK: Never

extension Never: FixedSized {
    @inlinable public var writer: Never { fatalError() }
}

// MARK: Tuple2

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
    @inlinable public static var _minStaticSize: Int {
        A._minStaticSize + A._minStaticSize
    }
    @inlinable public static var _maxStaticSize: Int? {
        guard
            let aMaxSize = A._maxStaticSize,
            let bMaxSize = B._maxStaticSize
        else { return nil }
        return aMaxSize + bMaxSize
    }
    @inlinable public var _underestimatedSize: Int { a._underestimatedSize + b._underestimatedSize }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        let writtenBytesA = try a._set(in: &buffer, at: offset)
        let writtenBytesB = try b._set(in: &buffer, at: offset + writtenBytesA)
        return writtenBytesA + writtenBytesB
    }
}

extension ByteBufferSerialisableTuple2: ByteBufferSerialisable where A: ByteBufferSerialisable, B: ByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        let writtenBytesA = a._set(in: &buffer, at: offset)
        let writtenBytesB = b._set(in: &buffer, at: offset + writtenBytesA)
        return writtenBytesA + writtenBytesB
    }
}

extension ByteBufferSerialisableTuple2: ThrowingFixedSized where A: ThrowingFixedSized, B: ThrowingFixedSized {
    //@inline(__always)
    @inlinable public var _size: Int {
        return a._size + b._size
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

extension ByteBufferSerialisableTuple2: FixedSized where A: FixedSized, B: FixedSized {
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

// MARK: Either

public enum ByteBufferSerialisableEither<A: ThrowingByteBufferSerialisable, B: ThrowingByteBufferSerialisable> {
    case a(A)
    case b(B)
}

extension ByteBufferSerialisableEither: ThrowingByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public static var _minStaticSize: Int {
        min(A._minStaticSize, A._minStaticSize)
    }
    @inlinable public static var _maxStaticSize: Int? {
        guard
            let aMaxSize = A._maxStaticSize,
            let bMaxSize = B._maxStaticSize
        else { return nil }
        return max(aMaxSize, bMaxSize)
    }
    @inlinable public var _underestimatedSize: Int {
        switch self {
        case .a(let a): return a._underestimatedSize
        case .b(let b): return b._underestimatedSize
        }
    }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        switch self {
        case .a(let a): return try a._set(in: &buffer, at: offset)
        case .b(let b): return try b._set(in: &buffer, at: offset)
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
}

extension ByteBufferSerialisableEither: ThrowingFixedSized where A: ThrowingFixedSized, B: ThrowingFixedSized {
    @inlinable public var _size: Int {
        switch self {
        case .a(let a): return a._size
        case .b(let b): return b._size
        }
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        switch self {
        case .a(let a): return try a._setUnsafe(in: buffer)
        case .b(let b): return try b._setUnsafe(in: buffer)
        }
    }
}

extension ByteBufferSerialisableEither: FixedSized where A: FixedSized, B: FixedSized {
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        switch self {
        case .a(let a): return a._setUnsafe(in: buffer)
        case .b(let b): return b._setUnsafe(in: buffer)
        }
    }
}

// MARK: Optional

extension Optional: ThrowingByteBufferSerialisable where Wrapped: ThrowingByteBufferSerialisable {
    @inlinable public static var _minStaticSize: Int { Wrapped._minStaticSize }
    @inlinable public static var _maxStaticSize: Int? { Wrapped._maxStaticSize }
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int {
        self?._underestimatedSize ?? 0
    }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        try self?._set(in: &buffer, at: offset) ?? 0
    }
}

extension Optional: ByteBufferSerialisable where Wrapped: ByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        self?._set(in: &buffer, at: offset) ?? 0
    }
}

extension Optional: ThrowingFixedSized where Wrapped: ThrowingFixedSized {
    @inlinable public var _size: Int {
        self?._size ?? 0
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        try self?._setUnsafe(in: buffer) ?? 0
    }
}

extension Optional: FixedSized where Wrapped: FixedSized {
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        self?._setUnsafe(in: buffer) ?? 0
    }
}

// MARK: Void aka Empty

public struct VoidSerialisable: FixedSized, StaticallySized {
    @inlinable public static var staticSize: Int { 0 }
    @inlinable init() {}
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int { 0 }
    @inlinable public var _size: Int { 0 }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int { 0 }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int { 0 }
}

// MARK: Result Builder

@resultBuilder public enum ByteBufferWriteBuilder {
    @inlinable public static func buildBlock() -> VoidSerialisable {
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

// MARK: ByteBuffer init and write

extension ByteBuffer {
    @inlinable public init(@ByteBufferWriteBuilder builder: () -> some ThrowingByteBufferSerialisable) throws {
        var buffer = ByteBuffer()
        try buffer.write(builder: builder)
        self = buffer
    }
    
    @inlinable public init(@ByteBufferWriteBuilder builder: () throws -> some ByteBufferSerialisable) throws {
        var buffer = ByteBuffer()
        try buffer.write(builder: builder)
        self = buffer
    }
    
    @inlinable public init(@ByteBufferWriteBuilder builder: () -> some ByteBufferSerialisable) {
        var buffer = ByteBuffer()
        buffer.write(builder: builder)
        self = buffer
    }
}

extension ByteBuffer {
    @discardableResult
    @inlinable public mutating func write(
        @ByteBufferWriteBuilder builder: () throws -> some ThrowingByteBufferSerialisable
    ) throws -> Int {
        try builder()._write(to: &self)
    }
    
    @discardableResult
    //@inline(__always)
    @inlinable public mutating func write(
        @ByteBufferWriteBuilder builder: () -> some ByteBufferSerialisable
    ) -> Int {
        builder()._write(to: &self)
    }
    
    @discardableResult
    //@inline(__always)
    @inlinable public mutating func write(
        @ByteBufferWriteBuilder builder: () throws -> some ByteBufferSerialisable
    ) rethrows -> Int {
        try builder()._write(to: &self)
    }
}

// MARK: FixedWidthInteger

extension FixedWidthInteger where Self: FixedSized & StaticallySized {
    @inlinable public var writer: Never { fatalError() }
    
    @inlinable public static var staticSize: Int { MemoryLayout<Self>.size }
    
    //@inline(__always)
    @inlinable public var _size: Int { MemoryLayout<Self>.size }
    //@inline(__always)
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        buffer.storeBytes(of: self.bigEndian, as: Self.self)
        return MemoryLayout<Self>.size
    }
}

extension Int8: FixedSized, StaticallySized {}
extension Int16: FixedSized, StaticallySized {}
extension Int32: FixedSized, StaticallySized {}
extension Int64: FixedSized, StaticallySized {}
extension UInt8: FixedSized, StaticallySized {}
extension UInt16: FixedSized, StaticallySized {}
extension UInt32: FixedSized, StaticallySized {}
extension UInt64: FixedSized, StaticallySized {}


// MARK: String

extension String: FixedSized {
    @inlinable public var writer: some FixedSized {
        self[...]
    }
}

extension Substring: FixedSized {
    @inlinable public var writer: Never { fatalError() }
    
    @inlinable public var _size: Int { self.utf8.count }
    
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        if let written = self.utf8.withContiguousStorageIfAvailable({ utf8Bytes in
            buffer.copyBytes(from: utf8Bytes)
            return utf8Bytes.count
        }) {
            // fast path, directly available
            return written
        } else {
            return self._setUnsafeSlowpath(in: buffer)
        }
    }
    
    @inline(never)
    @inlinable
    internal func _setUnsafeSlowpath(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        // slow path, let's try to force the string to be native
        if let written = (self + "").utf8.withContiguousStorageIfAvailable({ utf8Bytes in
            buffer.copyBytes(from: utf8Bytes)
            return utf8Bytes.count
        }) {
            return written
        } else {
            buffer.copyBytes(from: self.utf8)
            return self.utf8.count
        }
    }
}

extension StaticString: FixedSized {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _size: Int { self.utf8CodeUnitCount }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        buffer.copyMemory(from: UnsafeRawBufferPointer(
            start: self.utf8Start,
            count: self.utf8CodeUnitCount
        ))
        return self.utf8CodeUnitCount
    }
}

public struct NullTerminatedString: FixedSized {
    @usableFromInline var string: String
    @inlinable public init(string: String) {
        self.string = string
    }
    @inlinable public var writer: some FixedSized {
        string
        UInt8(0)
    }
}

public struct NullTerminatedSubstring: FixedSized {
    @usableFromInline var string: Substring
    @inlinable public init(string: Substring) {
        self.string = string
    }
    @inlinable public var writer: some FixedSized {
        string
        UInt8(0)
    }
}

// MARK: ByteBuffer

extension ByteBuffer: FixedSized {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _size: Int {
        self.readableBytes
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        self.withUnsafeReadableBytes { readBuffer -> Int in
            buffer.copyMemory(from: readBuffer)
            return readBuffer.count
        }
    }
}

// MARK: DispatchData

import Dispatch

extension DispatchData: FixedSized {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _size: Int {
        self.count
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        let allBytes = self.count
        self.copyBytes(to: buffer, count: allBytes)
        return allBytes
    }
}

// MARK: Repeated

extension Repeated: ThrowingByteBufferSerialisable, ThrowingFixedSized, ByteBufferSerialisable, FixedSized where Element == UInt8 {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _size: Int { self.count }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        buffer.initializeMemory(as: Element.self, repeating: self.repeatedValue)
        return self.count
    }
}

// MARK: LengthPrefixed

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
    @inlinable public var writer: Never { fatalError() }
    @inlinable public static var _minStaticSize: Int { Header.staticSize + Body._minStaticSize }
    @inlinable public static var _maxStaticSize: Int? {
        guard let bodyMaxStaticSize = Body._maxStaticSize else { return nil }
        return Header.staticSize + bodyMaxStaticSize
    }
    
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
}

extension LengthPrefixed: ThrowingFixedSized where Header: ThrowingFixedSized, Body: ThrowingFixedSized {
    @inlinable public var _size: Int {
        return Header.staticSize + body._size
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
    @inlinable public static var staticSize: Int { Header.staticSize + Body.staticSize }
}

extension LengthPrefixed where Header: FixedWidthInteger {
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

// MARK: ByteBufferWriter

public struct ByteBufferWriter: ByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    
    @usableFromInline var underestimatedSize: Int
    @usableFromInline var write: @Sendable (inout ByteBuffer) -> ()
    @inlinable public init(underestimatedSize: Int = 0, write: @escaping @Sendable (inout ByteBuffer) -> Void) {
        self.underestimatedSize = underestimatedSize
        self.write = write
    }
    
    @inlinable public var _underestimatedSize: Int { 0 }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.moveWriterIndex(to: offset)
        write(&buffer)
        let bytesWritten = buffer.writerIndex - offset
        assert(bytesWritten >= 0)
        return bytesWritten
    }
}

// MARK: Result

extension Result: ThrowingByteBufferSerialisable where Success: ThrowingByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    
    @inlinable public var _underestimatedSize: Int {
        switch self {
        case .success(let value): return value._underestimatedSize
        case .failure: return 0
        }
    }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int {
        switch self {
        case .success(let writer):
            return try writer._set(in: &buffer, at: offset)
        case .failure(let error):
            throw error
        }
    }
}

extension Result: ThrowingFixedSized where Success: ThrowingFixedSized {
    @inlinable public var _size: Int {
        switch self {
        case .success(let value): return value._size
        case .failure: return 0
        }
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        switch self {
        case .success(let writer):
            return try writer._setUnsafe(in: buffer)
        case .failure(let error):
            throw error
        }
    }
}

extension Result: StaticallySized where Success: StaticallySized {
    @inlinable public static var staticSize: Int { Success.staticSize }
}

