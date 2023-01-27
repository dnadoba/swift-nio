//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

final class ByteBufferReadWriteMultipleIntegersBenchmark<I: FixedWidthInteger>: Benchmark {
    private let iterations: Int
    private let numberOfInts: Int
    private var buffer: ByteBuffer = ByteBuffer()

    init(iterations: Int, numberOfInts: Int) {
        self.iterations = iterations
        self.numberOfInts = numberOfInts
    }

    func setUp() throws {
        self.buffer.reserveCapacity(self.numberOfInts * MemoryLayout<I>.size)
    }

    func tearDown() {
    }

    func run() throws -> Int {
        var result: I = 0
        for _ in 0..<self.iterations {
            for i in I(0)..<I(10) {
                self.buffer.writeInteger(i)
            }
            for _ in I(0)..<I(10) {
                result = result &+ self.buffer.readInteger(as: I.self)!
            }
        }
        precondition(result == I(self.iterations) * 45)
        return self.buffer.readableBytes
    }
}

final class ByteBufferMultiReadWriteTenIntegersBenchmark<I: FixedWidthInteger>: Benchmark {
    private let iterations: Int
    private var buffer: ByteBuffer = ByteBuffer()

    init(iterations: Int) {
        self.iterations = iterations
    }

    func setUp() throws {
        self.buffer.reserveCapacity(10 * MemoryLayout<I>.size)
    }

    func tearDown() {
    }

    func run() throws -> Int {
        var result: I = 0
        for _ in 0..<self.iterations {
            self.buffer.writeMultipleIntegers(
                0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
                as: (I, I, I, I, I, I, I, I, I, I).self
            )
            let value = self.buffer.readMultipleIntegers(as: (I, I, I, I, I, I, I, I, I, I).self)!
            result = result &+ value.0
            result = result &+ value.1
            result = result &+ value.2
            result = result &+ value.3
            result = result &+ value.4
            result = result &+ value.5
            result = result &+ value.6
            result = result &+ value.7
            result = result &+ value.8
            result = result &+ value.9
        }
        precondition(result == I(self.iterations) * 45)
        return self.buffer.readableBytes
    }
}

func build<Writer>(
    @ByteBufferWriteBuilder builder: () -> Writer
) -> Writer {
    builder()
}

struct TenIntegers<I: ByteBufferSerialisable>: ByteBufferSerialisable {
    var i0: I
    var i1: I
    var i2: I
    var i3: I
    var i4: I
    var i5: I
    var i6: I
    var i7: I
    var i8: I
    var i9: I
    
    var writer: some ByteBufferSerialisable {
        i0
        i1
        i2
        i3
        i4
        i5
        i6
        i7
        i8
        i9
    }
}

final class ByteBufferResultBuilderWriteTenIntegersAndReadMultiBenchmark<I: FixedWidthInteger & NonThrowingByteBufferSerialisable>: Benchmark {
    private let iterations: Int
    private var buffer: ByteBuffer = ByteBuffer()

    init(iterations: Int) {
        self.iterations = iterations
    }

    func setUp() throws {
        self.buffer.reserveCapacity(10 * MemoryLayout<I>.size)
    }

    func tearDown() {
    }

    func run() throws -> Int {
        var result: I = 0
        let iterations = self.iterations
        for _ in 0..<iterations {
            let writer = build {
                TenIntegers<I>(
                    i0: 0,
                    i1: 1,
                    i2: 2,
                    i3: 3,
                    i4: 4,
                    i5: 5,
                    i6: 6,
                    i7: 7,
                    i8: 8,
                    i9: 9
                )
            }
            try self.buffer.write { writer }
            let value = self.buffer.readMultipleIntegers(as: (I, I, I, I, I, I, I, I, I, I).self)!
            result = result &+ value.0
            result = result &+ value.1
            result = result &+ value.2
            result = result &+ value.3
            result = result &+ value.4
            result = result &+ value.5
            result = result &+ value.6
            result = result &+ value.7
            result = result &+ value.8
            result = result &+ value.9
        }
        precondition(result == I(self.iterations) * 45)
        return self.buffer.readableBytes
    }
}

final class RawResultBuilderWriteTenIntegersAndReadMultiBenchmark<I: FixedWidthInteger & StaticallySizedRawWriterProtocol>: Benchmark {
    private let iterations: Int
    private var buffer: ByteBuffer = ByteBuffer()

    init(iterations: Int) {
        self.iterations = iterations
    }

    func setUp() throws {
        self.buffer.reserveCapacity(10 * MemoryLayout<I>.size)
    }

    func tearDown() {
    }

    func run() throws -> Int {
        var result: I = 0
        let iterations = self.iterations
        for _ in 0..<iterations {
            self.buffer.writeRaw {
                I(0)
                I(1)
                I(2)
                I(3)
                I(4)
                I(5)
                I(6)
                I(7)
                I(8)
                I(9)
            }
            let value = self.buffer.readMultipleIntegers(as: (I, I, I, I, I, I, I, I, I, I).self)!
            result = result &+ value.0
            result = result &+ value.1
            result = result &+ value.2
            result = result &+ value.3
            result = result &+ value.4
            result = result &+ value.5
            result = result &+ value.6
            result = result &+ value.7
            result = result &+ value.8
            result = result &+ value.9
        }
        precondition(result == I(self.iterations) * 45)
        return self.buffer.readableBytes
    }
}
