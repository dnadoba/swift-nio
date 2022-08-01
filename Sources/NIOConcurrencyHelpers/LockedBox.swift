//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2022 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if swift(>=5.5) && canImport(_Concurrency)
public final class NIOLockedBox<Value: Sendable>: @unchecked Sendable {
    @usableFromInline let lock: Lock = .init()
    @usableFromInline var value: Value
    @inlinable public init(_ value: Value) {
        self.value = value
    }
}
#else
public final class NIOLockedBox<Value> {
    @usableFromInline let lock: Lock = .init()
    @usableFromInline var value: Value
    @inlinable public init(_ value: Value) {
        self.value = value
    }
}
#endif

extension NIOLockedBox {
    @inlinable public func withValue<Result>(
        _ modify: (inout Value) throws -> Result
    ) rethrows -> Result {
        try lock.withLock {
            try modify(&value)
        }
    }
}
