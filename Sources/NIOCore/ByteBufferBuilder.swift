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

@rethrows
public protocol ByteBufferSerialisable {
    // hidden private API implemented by primitive types
    // we might want to merge _underestimatedSize and _write into a single method
    // otherwise we need potentially need two passes through all serialisables
    var _underestimatedSize: Int { get }
    func _set(in buffer: inout ByteBuffer, at offset: Int) throws -> Int
    
    var _size: Int? { get }
    func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int
    
    // public API
    associatedtype Writer: ByteBufferSerialisable
    @ByteBufferWriteBuilder var writer: Writer { get }
}

extension ByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        writer._underestimatedSize
    }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) rethrows -> Int {
        try writer._set(in: &buffer, at: offset)
    }
    
    @inlinable public var _size: Int? { writer._size }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) rethrows -> Int {
        try writer._setUnsafe(in: buffer)
    }
}

public protocol NonThrowingByteBufferSerialisable: ByteBufferSerialisable where Writer: NonThrowingByteBufferSerialisable {
    func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int
    func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int
}

extension NonThrowingByteBufferSerialisable {
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

extension Never: NonThrowingByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int { fatalError() }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int { fatalError() }
    @inlinable public var writer: Never { fatalError() }
}

//extension Never: StaticallySized {}

extension ByteBufferSerialisable where Writer: StaticallySized {
    @inlinable public static var staticSize: Int { Writer.staticSize }
}

@usableFromInline
struct ByteBufferSerialisableTuple2<A: ByteBufferSerialisable, B: ByteBufferSerialisable> {
    @usableFromInline var a: A
    @usableFromInline var b: B
    @inlinable init(a: A, b: B) {
        self.a = a
        self.b = b
    }
}

extension ByteBufferSerialisableTuple2: ByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int { a._underestimatedSize + b._underestimatedSize }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) rethrows -> Int {
        let writtenBytesA = try a._set(in: &buffer, at: offset)
        let writtenBytesB = try b._set(in: &buffer, at: offset + writtenBytesA)
        return writtenBytesA + writtenBytesB
    }
    
    //@inline(__always)
    @inlinable public var _size: Int? {
        guard let aSize = a._size, let bSize = b._size else { return nil }
        return aSize + bSize
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) rethrows -> Int {
        precondition(buffer.count >= _size!, "buffer.count >= _size! \(#function)")
        let writtenBytesA = try a._setUnsafe(in: buffer)
        
        let advancedPointer = UnsafeMutableRawBufferPointer(rebasing: buffer.dropFirst(writtenBytesA))
        precondition(advancedPointer.count >= b._size!, "pointer advancing failed")
        let writtenBytesB = try b._setUnsafe(in: advancedPointer)
        return writtenBytesA + writtenBytesB
    }
}

extension ByteBufferSerialisableTuple2: NonThrowingByteBufferSerialisable where A: NonThrowingByteBufferSerialisable, B: NonThrowingByteBufferSerialisable {
    @inlinable func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        let writtenBytesA = a._set(in: &buffer, at: offset)
        let writtenBytesB = b._set(in: &buffer, at: offset + writtenBytesA)
        return writtenBytesA + writtenBytesB
    }
    //@inline(__always)
    @inlinable func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        //guard buffer.count >= a._size! else { fatalError("buffer.count >= _size! \(#function)") }
        let writtenBytesA = a._setUnsafe(in: buffer)
        
        let advancedPointer = UnsafeMutableRawBufferPointer(fastRebase: buffer.dropFirst(writtenBytesA))
        //guard advancedPointer.count >= b._size! else { fatalError("pointer advancing failed \(#function)") }
        let writtenBytesB = b._setUnsafe(in: advancedPointer)
        return writtenBytesA &+ writtenBytesB
    }
}

extension ByteBufferSerialisableTuple2: StaticallySized where A: StaticallySized, B: StaticallySized {
    @inlinable static var staticSize: Int { A.staticSize + B.staticSize }
}

@usableFromInline
enum ByteBufferSerialisableEither<A: ByteBufferSerialisable, B: ByteBufferSerialisable> {
    case a(A)
    case b(B)
}

extension ByteBufferSerialisableEither: ByteBufferSerialisable {
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
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) rethrows -> Int {
        switch self {
        case .a(let a): return try a._set(in: &buffer, at: offset)
        case .b(let b): return try b._set(in: &buffer, at: offset)
        }
    }
    
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) rethrows -> Int {
        switch self {
        case .a(let a): return try a._setUnsafe(in: buffer)
        case .b(let b): return try b._setUnsafe(in: buffer)
        }
    }
}

extension ByteBufferSerialisableEither: NonThrowingByteBufferSerialisable where A: NonThrowingByteBufferSerialisable, B: NonThrowingByteBufferSerialisable {
    @inlinable func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        switch self {
        case .a(let a): return a._set(in: &buffer, at: offset)
        case .b(let b): return b._set(in: &buffer, at: offset)
        }
    }
    
    @inlinable func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        switch self {
        case .a(let a): return a._setUnsafe(in: buffer)
        case .b(let b): return b._setUnsafe(in: buffer)
        }
    }
}

extension Optional: ByteBufferSerialisable where Wrapped: ByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int {
        self?._underestimatedSize ?? 0
    }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) rethrows -> Int {
        try self?._set(in: &buffer, at: offset) ?? 0
    }
    
    @inlinable public var _size: Int? {
        guard let self else { return 0 }
        return self._size
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) rethrows -> Int {
        try self?._setUnsafe(in: buffer) ?? 0
    }
}

extension Optional: NonThrowingByteBufferSerialisable where Wrapped: NonThrowingByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        self?._set(in: &buffer, at: offset) ?? 0
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int {
        self?._setUnsafe(in: buffer) ?? 0
    }
}

@resultBuilder public enum ByteBufferWriteBuilder {

    //@inline(__always)
    @inlinable public static func buildPartialBlock<First: ByteBufferSerialisable>(first: First) -> First {
        first
    }
    //@inline(__always)
    @inlinable public static func buildPartialBlock<First: ByteBufferSerialisable, Second: ByteBufferSerialisable>(
        accumulated: First,
        next: Second
    ) -> some ByteBufferSerialisable {
        ByteBufferSerialisableTuple2(a: accumulated, b: next)
    }
    @inlinable public static func buildPartialBlock<First: NonThrowingByteBufferSerialisable, Second: NonThrowingByteBufferSerialisable>(
        accumulated: First,
        next: Second
    ) -> some NonThrowingByteBufferSerialisable {
        ByteBufferSerialisableTuple2(a: accumulated, b: next)
    }
    
    @inlinable public static func buildPartialBlock<First: ByteBufferSerialisable & StaticallySized, Second: ByteBufferSerialisable & StaticallySized>(
        accumulated: First,
        next: Second
    ) -> some ByteBufferSerialisable & StaticallySized {
        ByteBufferSerialisableTuple2(a: accumulated, b: next)
    }
    @inlinable public static func buildPartialBlock<First: NonThrowingByteBufferSerialisable & StaticallySized, Second: NonThrowingByteBufferSerialisable & StaticallySized>(
        accumulated: First,
        next: Second
    ) -> some NonThrowingByteBufferSerialisable & StaticallySized {
        ByteBufferSerialisableTuple2(a: accumulated, b: next)
    }
    
    @inlinable public static func buildEither<First: ByteBufferSerialisable, Second: ByteBufferSerialisable>(
        first component: First
    ) -> some ByteBufferSerialisable {
        ByteBufferSerialisableEither<First, Second>.a(component)
    }
    @inlinable public static func buildEither<First: ByteBufferSerialisable, Second: ByteBufferSerialisable>(
        second component: Second
    ) -> some ByteBufferSerialisable {
        ByteBufferSerialisableEither<First, Second>.b(component)
    }
    
    @inlinable static func buildEither<First: NonThrowingByteBufferSerialisable, Second: NonThrowingByteBufferSerialisable>(
        first component: First
    ) -> some NonThrowingByteBufferSerialisable {
        ByteBufferSerialisableEither<First, Second>.a(component)
    }
    @inlinable public static func buildEither<First: NonThrowingByteBufferSerialisable, Second: NonThrowingByteBufferSerialisable>(
        second component: Second
    ) -> some NonThrowingByteBufferSerialisable {
        ByteBufferSerialisableEither<First, Second>.b(component)
    }
    
    @inlinable public static func buildOptional<Component: ByteBufferSerialisable>(_ component: Component?) -> Component? {
        component
    }
    @inlinable public static func buildLimitedAvailability<Component>(component: Component) -> Component {
        component
    }
    // TODO: should we add buildArray as well? use case?
}

extension ByteBuffer {
    @inlinable public init(@ByteBufferWriteBuilder builder: () -> some ByteBufferSerialisable) rethrows {
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
    
    @inlinable public init(@ByteBufferWriteBuilder builder: () -> some NonThrowingByteBufferSerialisable) {
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
        @ByteBufferWriteBuilder builder: () -> some ByteBufferSerialisable
    ) rethrows -> Int {
        let serialisable = builder()
        
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
        @ByteBufferWriteBuilder builder: () -> some NonThrowingByteBufferSerialisable
    ) -> Int {
        let serialisable = builder()
        
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



extension FixedWidthInteger where Self: NonThrowingByteBufferSerialisable & StaticallySized {
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

extension Int8: NonThrowingByteBufferSerialisable, StaticallySized {}
extension Int16: NonThrowingByteBufferSerialisable, StaticallySized {}
extension Int32: NonThrowingByteBufferSerialisable, StaticallySized {}
extension Int64: NonThrowingByteBufferSerialisable, StaticallySized {}
extension UInt8: NonThrowingByteBufferSerialisable, StaticallySized {}
extension UInt16: NonThrowingByteBufferSerialisable, StaticallySized {}
extension UInt32: NonThrowingByteBufferSerialisable, StaticallySized {}
extension UInt64: NonThrowingByteBufferSerialisable, StaticallySized {}

extension String: NonThrowingByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        self.utf8.count
    }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.setString(self, at: offset)
    }
    
    @inlinable public var _size: Int? { nil }
    
    @inlinable public var writer: Never { fatalError() }
}

extension Substring: NonThrowingByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        self.utf8.count
    }
    
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.setSubstring(self, at: offset)
    }
    
    @inlinable public var _size: Int? { nil }
    @inlinable public var writer: Never { fatalError() }
}

extension ByteBuffer: NonThrowingByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        self.readableBytes
    }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.setBuffer(self, at: offset)
    }
    @inlinable public var _size: Int? { nil }
    @inlinable public var writer: Never { fatalError() }
}

public struct LengthPrefixed<LengthPrefixInteger: FixedWidthInteger, Message: ByteBufferSerialisable>: ByteBufferSerialisable {
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



