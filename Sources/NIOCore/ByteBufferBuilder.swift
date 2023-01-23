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
    func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) throws -> Int?
    
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
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) rethrows -> Int? {
        try writer._setUnsafe(in: buffer)
    }
}

public protocol NonThrowingByteBufferSerialisable: ByteBufferSerialisable where Writer: NonThrowingByteBufferSerialisable {
    func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int
    func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int?
}

extension NonThrowingByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        writer._set(in: &buffer, at: offset)
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int? {
        writer._setUnsafe(in: buffer)
    }
}

extension Never: NonThrowingByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int { fatalError() }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int { fatalError() }
    @inlinable public var writer: Never { fatalError() }
}

public struct ByteBufferSerialisableTuple2<A: ByteBufferSerialisable, B: ByteBufferSerialisable> {
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
    
    @inlinable public var _size: Int? {
        guard let aSize = a._size, let bSize = b._size else { return nil }
        return aSize + bSize
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) rethrows -> Int? {
        precondition(buffer.count >= _size!, "buffer.count >= _size! \(#function)")
        guard let writtenBytesA = try a._setUnsafe(in: buffer) else {
            return nil
        }
        
        let advancedPointer = UnsafeMutableRawBufferPointer(rebasing: buffer.dropFirst(writtenBytesA))
        precondition(advancedPointer.count >= b._size!, "pointer advancing failed")
        guard let writtenBytesB = try b._setUnsafe(in: advancedPointer) else {
            return nil
        }
        return writtenBytesA + writtenBytesB
    }
}

extension ByteBufferSerialisableTuple2: NonThrowingByteBufferSerialisable where A: NonThrowingByteBufferSerialisable, B: NonThrowingByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        let writtenBytesA = a._set(in: &buffer, at: offset)
        let writtenBytesB = b._set(in: &buffer, at: offset + writtenBytesA)
        return writtenBytesA + writtenBytesB
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int? {
        guard buffer.count >= a._size! else { fatalError("buffer.count >= _size! \(#function)") }
        guard let writtenBytesA = a._setUnsafe(in: buffer) else {
            return nil
        }
        
        let advancedPointer = UnsafeMutableRawBufferPointer(rebasing: buffer.dropFirst(writtenBytesA))
        guard advancedPointer.count >= b._size! else { fatalError("pointer advancing failed \(#function)") }
        guard let writtenBytesB = b._setUnsafe(in: advancedPointer) else {
            return nil
        }
        return writtenBytesA + writtenBytesB
    }
}

public enum ByteBufferSerialisableEither<A: ByteBufferSerialisable, B: ByteBufferSerialisable> {
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
    
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) rethrows -> Int? {
        switch self {
        case .a(let a): return try a._setUnsafe(in: buffer)
        case .b(let b): return try b._setUnsafe(in: buffer)
        }
    }
}

extension ByteBufferSerialisableEither: NonThrowingByteBufferSerialisable where A: NonThrowingByteBufferSerialisable, B: NonThrowingByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        switch self {
        case .a(let a): return a._set(in: &buffer, at: offset)
        case .b(let b): return b._set(in: &buffer, at: offset)
        }
    }
    
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int? {
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
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) rethrows -> Int? {
        guard let self else {
            return 0
        }
        return try self._setUnsafe(in: buffer)
    }
}

extension Optional: NonThrowingByteBufferSerialisable where Wrapped: NonThrowingByteBufferSerialisable {
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        self?._set(in: &buffer, at: offset) ?? 0
    }
    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int? {
        guard let self else {
            return 0
        }
        return self._setUnsafe(in: buffer)
    }
}

@resultBuilder public enum ByteBufferWriteBuilder {
    @inlinable public static func buildPartialBlock<First: ByteBufferSerialisable>(first: First) -> First {
        first
    }
    @inlinable public static func buildPartialBlock<First: ByteBufferSerialisable, Second: ByteBufferSerialisable>(
        accumulated: First,
        next: Second
    ) -> ByteBufferSerialisableTuple2<First, Second> {
        ByteBufferSerialisableTuple2(a: accumulated, b: next)
    }
    @inlinable public static func buildEither<First: ByteBufferSerialisable, Second: ByteBufferSerialisable>(
        first component: First
    ) -> ByteBufferSerialisableEither<First, Second> {
        ByteBufferSerialisableEither.a(component)
    }
    @inlinable public static func buildEither<First: ByteBufferSerialisable, Second: ByteBufferSerialisable>(
        second component: Second
    ) -> ByteBufferSerialisableEither<First, Second> {
        ByteBufferSerialisableEither.b(component)
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
                guard let writtenBytes else {
                    preconditionFailure("failed to write to byte buffer through `_setUnsafe(in:)` even though `_size` has returned a value if \(size)")
                }
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
                guard let writtenBytes else {
                    preconditionFailure("failed to write to byte buffer through `_setUnsafe(in:)` even though `_size` has returned a value if \(size)")
                }
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
                guard let writtenBytes else {
                    preconditionFailure("failed to write to byte buffer through `_setUnsafe(in:)` even though `_size` has returned a value if \(size)")
                }
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
    @inlinable public mutating func write(
        @ByteBufferWriteBuilder builder: () -> some NonThrowingByteBufferSerialisable
    ) -> Int {
        let serialisable = builder()
        
        if let size = serialisable._size {
            if size != 40 {
                print("size", size)
            }
            return self.writeWithUnsafeMutableBytes(minimumWritableBytes: size) { buffer in
                let writtenBytes = serialisable._setUnsafe(in: buffer)
                guard let writtenBytes else {
                    preconditionFailure("failed to write to byte buffer through `_setUnsafe(in:)` even though `_size` has returned a value if \(size)")
                }
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



extension FixedWidthInteger where Self: NonThrowingByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    
    @inlinable public var _underestimatedSize: Int { MemoryLayout<Self>.size }
    @inlinable public func _set(in buffer: inout ByteBuffer, at offset: Int) -> Int {
        buffer.setInteger(self, at: offset)
    }
    
    @inlinable public var _size: Int? { nil }
//    @inlinable public func _setUnsafe(in buffer: UnsafeMutableRawBufferPointer) -> Int? {
//        precondition(buffer.count >= _size!, "buffer.count >= _size! \(#function)")
//        var mutableSelf = self.bigEndian
//        buffer.baseAddress!.copyMemory(from: &mutableSelf, byteCount: MemoryLayout<Self>.size)
//
//        return MemoryLayout<Self>.size
//    }
}

extension Int8: NonThrowingByteBufferSerialisable {}
extension Int16: NonThrowingByteBufferSerialisable {}
extension Int32: NonThrowingByteBufferSerialisable {}
extension Int64: NonThrowingByteBufferSerialisable {}
extension UInt8: NonThrowingByteBufferSerialisable {}
extension UInt16: NonThrowingByteBufferSerialisable {}
extension UInt32: NonThrowingByteBufferSerialisable {}
extension UInt64: NonThrowingByteBufferSerialisable {}

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



