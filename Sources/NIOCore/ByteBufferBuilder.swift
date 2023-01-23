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
    // we might want
    func _write(to buffer: inout ByteBuffer) rethrows -> Int
    
    // public API
    associatedtype Writer: ByteBufferSerialisable
    @ByteBufferWriteBuilder var writer: Writer { get }
}

extension ByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        writer._underestimatedSize
    }
    @inlinable public func _write(to buffer: inout ByteBuffer) rethrows -> Int {
        try writer._write(to: &buffer)
    }
}

extension Never: ByteBufferSerialisable {
    public var _underestimatedSize: Int { fatalError() }
    public func _write(to buffer: inout ByteBuffer) -> Int { fatalError() }
    public var writer: Never { fatalError() }
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
    public var writer: Never { fatalError() }
    public var _underestimatedSize: Int { a._underestimatedSize + b._underestimatedSize }
    @inlinable public func _write(to buffer: inout ByteBuffer) rethrows -> Int {
        try a._write(to: &buffer) + b._write(to: &buffer)
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
    @inlinable public func _write(to buffer: inout ByteBuffer) rethrows -> Int {
        switch self {
        case .a(let a): return try a._write(to: &buffer)
        case .b(let b):  return try b._write(to: &buffer)
        }
    }
}

extension Optional: ByteBufferSerialisable where Wrapped: ByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int {
        self?._underestimatedSize ?? 0
    }
    @inlinable public func _write(to buffer: inout ByteBuffer) rethrows -> Int {
        try self?._write(to: &buffer) ?? 0
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
    public static func buildEither<First: ByteBufferSerialisable, Second: ByteBufferSerialisable>(
        first component: First
    ) -> ByteBufferSerialisableEither<First, Second> {
        ByteBufferSerialisableEither.a(component)
    }
    public static func buildEither<First: ByteBufferSerialisable, Second: ByteBufferSerialisable>(
        second component: Second
    ) -> ByteBufferSerialisableEither<First, Second> {
        ByteBufferSerialisableEither.b(component)
    }
    public static func buildOptional<Component: ByteBufferSerialisable>(_ component: Component?) -> Component? {
        component
    }
    public static func buildLimitedAvailability<Component>(component: Component) -> Component {
        component
    }
    // TODO: should we add buildArray as well? use case?
}

extension ByteBuffer {
    @inlinable public init(@ByteBufferWriteBuilder builder: () -> some ByteBufferSerialisable) rethrows {
        let serialisable = builder()
        var buffer = ByteBuffer(allocator: .init(), startingCapacity: serialisable._underestimatedSize)
        _ = try serialisable._write(to: &buffer)
        self = buffer
    }
}

extension ByteBuffer {
    @inlinable public mutating func write(
        @ByteBufferWriteBuilder builder: () -> some ByteBufferSerialisable
    ) rethrows -> Int {
        let serialisable = builder()
        self.reserveCapacity(minimumWritableBytes: serialisable._underestimatedSize)
        return try serialisable._write(to: &self)
    }
}

extension FixedWidthInteger where Self: ByteBufferSerialisable {
    @inlinable public var writer: Never { fatalError() }
    @inlinable public var _underestimatedSize: Int { MemoryLayout<Self>.size }
    @inlinable public func _write(to buffer: inout ByteBuffer) {
        buffer.writeInteger(self)
    }
}

extension Int8: ByteBufferSerialisable {}
extension Int16: ByteBufferSerialisable {}
extension Int32: ByteBufferSerialisable {}
extension Int64: ByteBufferSerialisable {}
extension UInt8: ByteBufferSerialisable {}
extension UInt16: ByteBufferSerialisable {}
extension UInt32: ByteBufferSerialisable {}
extension UInt64: ByteBufferSerialisable {}

extension String: ByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        self.utf8.count
    }
    
    @inlinable public func _write(to buffer: inout ByteBuffer) -> Int {
        buffer.writeString(self)
    }
    @inlinable public var writer: Never { fatalError() }
}

extension ByteBuffer: ByteBufferSerialisable {
    @inlinable public var _underestimatedSize: Int {
        self.readableBytes
    }
    @inlinable public func _write(to buffer: inout ByteBuffer) -> Int {
        buffer.writeImmutableBuffer(self)
    }
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
    
    @inlinable public func _write(to buffer: inout ByteBuffer) throws {
        try buffer.writeLengthPrefixed(as: LengthPrefixInteger.self) { buffer in
            try message._write(to: &buffer)
        }
    }
    @inlinable public var writer: Never { fatalError() }
}



