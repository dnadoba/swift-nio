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

import NIOCore
import XCTest

final class ByteBufferWriterTests: XCTestCase {
    func testWriteMultipleIntegers() {
        var buffer = ByteBuffer {
            Int8(1)
            Int16(2)
            Int32(3)
            Int64(4)
            UInt8(5)
            UInt16(6)
            UInt32(7)
            UInt64(8)
        }
        XCTAssertEqual(Int8(1), buffer.readInteger())
        XCTAssertEqual(Int16(2), buffer.readInteger())
        XCTAssertEqual(Int32(3), buffer.readInteger())
        XCTAssertEqual(Int64(4), buffer.readInteger())
        XCTAssertEqual(UInt8(5), buffer.readInteger())
        XCTAssertEqual(UInt16(6), buffer.readInteger())
        XCTAssertEqual(UInt32(7), buffer.readInteger())
        XCTAssertEqual(UInt64(8), buffer.readInteger())
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
    }
    
    func testOptional() {
        let optionalInteger: Optional = UInt8(2)
        var buffer = ByteBuffer {
            if let optionalInteger {
                optionalInteger
            }
        }
        XCTAssertEqual(UInt8(2), buffer.readInteger())
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
    }
    
    func testIfElse() {
        let randomBool = Bool.random()
        var buffer = ByteBuffer {
            if randomBool {
                UInt8(2)
            } else {
                UInt16(3)
            }
        }
        if randomBool {
            XCTAssertEqual(UInt8(2), buffer.readInteger())
        } else {
            XCTAssertEqual(UInt16(3), buffer.readInteger())
        }
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
    }
    
    func testIfElseWithEmptyElseBranch() {
        let randomBool = Bool.random()
        var buffer = ByteBuffer {
            if randomBool {
                UInt8(2)
            } else { }
        }
        if randomBool {
            XCTAssertEqual(UInt8(2), buffer.readInteger())
        } else { }
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
    }
    
    func testIfElseThrow() throws {
        struct MyError: Error {}
        let boolTrue = true
        var buffer = try ByteBuffer {
            if boolTrue {
                UInt8(1)
            } else {
                throw MyError()
            }
        }
        
        XCTAssertEqual(UInt8(1), buffer.readInteger())
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
        
        let boolFalse = false
        
        XCTAssertThrowsError(try ByteBuffer {
            if boolFalse {
                UInt8(1)
            } else {
                throw MyError()
            }
        })
    }
    
    func testComposition() {
        struct CustomStruct: NonThrowingByteBufferSerialisable {
            var a: UInt8
            var b: UInt16
            var nested: Nested
            
            var writer: some NonThrowingByteBufferSerialisable {
                a
                b
                nested
            }
            
            enum Nested: NonThrowingByteBufferSerialisable {
                case c(UInt32)
                case d(UInt64)
                
                var writer: some NonThrowingByteBufferSerialisable {
                    switch self {
                    case .c(let c):
                        c
                    case .d(let d):
                        d
                    }
                }
            }
        }
        
        var buffer = ByteBuffer {
            CustomStruct(a: 1, b: 2, nested: .c(3))
            CustomStruct(a: 4, b: 5, nested: .d(6))
        }
        XCTAssertEqual(buffer.readInteger(), UInt8(1))
        XCTAssertEqual(buffer.readInteger(), UInt16(2))
        XCTAssertEqual(buffer.readInteger(), UInt32(3))
        XCTAssertEqual(buffer.readInteger(), UInt8(4))
        XCTAssertEqual(buffer.readInteger(), UInt16(5))
        XCTAssertEqual(buffer.readInteger(), UInt64(6))
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
    }
    
    func testMultipleWrites() {
        var buffer = ByteBuffer()
        buffer.write {
            UInt32(1)
            UInt32(2)
        }
        buffer.write {
            UInt32(3)
            UInt32(4)
        }
        XCTAssertEqual(UInt32(1), buffer.readInteger())
        XCTAssertEqual(UInt32(2), buffer.readInteger())
        XCTAssertEqual(UInt32(3), buffer.readInteger())
        XCTAssertEqual(UInt32(4), buffer.readInteger())
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
    }
    func testManyWrites() {
        var buffer = ByteBuffer()
        for i in UInt32(0)..<100 {
            buffer.write {
                UInt32(i + 0)
                UInt32(i + 1)
                UInt32(i + 2)
                UInt32(i + 3)
                UInt32(i + 4)
                UInt32(i + 5)
            }
        }
        for i in UInt32(0)..<100 {
            guard let result = buffer.readMultipleIntegers(as: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32).self) else {
                return XCTFail()
            }
            XCTAssert(result == (
                i + 0,
                i + 1,
                i + 2,
                i + 3,
                i + 4,
                i + 5
            ))
        }
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
    }
    
    func testLengthPrefix() throws {
        var buffer = try ByteBuffer {
            LengthPrefixed { bodyLength in
                IPv4Header(
                    totalLength: try UInt16(messageLength: 20 + bodyLength),
                    protocol: .reservedForTesting,
                    headerChecksum: 0,
                    sourceIpAddress: .init(127, 0, 0, 1),
                    destinationIpAddress: .init(127, 0, 0, 1)
                ).withChecksum()
            } body: {
                UInt8(1)
                UInt16(2)
                UInt32(3)
                "My message Body"
            }
        }
        
        let ipv4Header = try XCTUnwrap(buffer.readIPv4Header())
        XCTAssertEqual(Int(ipv4Header.totalLength), 20 + buffer.readableBytes)
        XCTAssertEqual(buffer.readInteger(), UInt8(1))
        XCTAssertEqual(buffer.readInteger(), UInt16(2))
        XCTAssertEqual(buffer.readInteger(), UInt32(3))
        XCTAssertEqual(buffer.readString(length: buffer.readableBytes), "My message Body")
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
    }
    
    func testByteBufferWriter() throws {
        var buffer = ByteBuffer {
            UInt8(1)
            ByteBufferWriter { buffer in
                buffer.writeInteger(UInt16(2))
                buffer.writeInteger(UInt32(3))
            }
            UInt64(4)
        }
        
        XCTAssertEqual(buffer.readInteger(), UInt8(1))
        XCTAssertEqual(buffer.readInteger(), UInt16(2))
        XCTAssertEqual(buffer.readInteger(), UInt32(3))
        XCTAssertEqual(buffer.readInteger(), UInt64(4))
        XCTAssertEqual(buffer.writerIndex, buffer.readerIndex)
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
