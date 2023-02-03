//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIOCore
import Dispatch

// Use unbuffered stdout to help detect exactly which test was running in the event of a crash.
setbuf(stdout, nil)

// MARK: Test Harness

var warning: String = ""
assert({
    print("======================================================")
    print("= YOU ARE RUNNING NIOPerformanceTester IN DEBUG MODE =")
    print("======================================================")
    warning = " <<< DEBUG MODE >>>"
    return true
    }())

public func measure(_ fn: () throws -> Int) rethrows -> [Double] {
    func measureOne(_ fn: () throws -> Int) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        _ = try fn()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / Double(TimeAmount.seconds(1).nanoseconds)
    }

    _ = try measureOne(fn) /* pre-heat and throw away */
    var measurements = Array(repeating: 0.0, count: 10)
    for i in 0..<10 {
        measurements[i] = try measureOne(fn)
    }

    return measurements
}

let limitSet = CommandLine.arguments.dropFirst()

public func measureAndPrint(desc: String, fn: () throws -> Int) rethrows -> Void {
    print("measuring\(warning): \(desc): ", terminator: "")
    let measurements = try measure(fn)
    print(measurements.reduce(into: "") { $0.append("\($1), ") })
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public func measure(_ fn: () async throws -> Int) async rethrows -> [Double] {
    func measureOne(_ fn: () async throws -> Int) async rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        _ = try await fn()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / Double(TimeAmount.seconds(1).nanoseconds)
    }

    _ = try await measureOne(fn) /* pre-heat and throw away */
    var measurements = Array(repeating: 0.0, count: 10)
    for i in 0..<10 {
        measurements[i] = try await measureOne(fn)
    }

    return measurements
}

@available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
public func measureAndPrint(desc: String, fn: () async throws -> Int) async rethrows -> Void {
    if limitSet.isEmpty || limitSet.contains(desc) {
        print("measuring\(warning): \(desc): ", terminator: "")
        let measurements = try await measure(fn)
        print(measurements.reduce(into: "") { $0.append("\($1), ") })
    } else {
        print("skipping '\(desc)', limit set = \(limitSet)")
    }
}

// MARK: Utilities

try measureAndPrint(
    desc: "bytebuffer_rw_10_uint32s",
    benchmark: ByteBufferReadWriteMultipleIntegersBenchmark<UInt32>(
        iterations: 100_000,
        numberOfInts: 10
    )
)

try measureAndPrint(
    desc: "bytebuffer_multi_rw_10_uint32s",
    benchmark: ByteBufferMultiReadWriteTenIntegersBenchmark<UInt32>(
        iterations: 1_000_000
    )
)

try measureAndPrint(
    desc: "bytebuffer_result_builder_rw_10_uint32s",
    benchmark: ByteBufferResultBuilderWriteTenIntegersAndReadMultiBenchmark<UInt32>(
        iterations: 1_000_000
    )
)
try measureAndPrint(
    desc: "raw_result_builder_rw_10_uint32s",
    benchmark: RawResultBuilderWriteTenIntegersAndReadMultiBenchmark<UInt32>(
        iterations: 1_000_000
    )
)

try measureAndPrint(
    desc: "bytebuffer_multi_rw_2x10_uint32s",
    benchmark: ByteBufferMultiReadWriteTenIntegersTwiceBenchmark<UInt32>(
        iterations: 1_000_000
    )
)

try measureAndPrint(
    desc: "bytebuffer_result_builder_rw_2x10_uint32s",
    benchmark: ByteBufferResultBuilderWriteTenIntegersTwiceAndReadMultiBenchmark<UInt32>(
        iterations: 1_000_000
    )
)

try measureAndPrint(
    desc: "byte_buffer_write_string_html_response",
    benchmark: ByteBufferWriteStringHTMLResponse(
        iterations: 100_000
    )
)

try measureAndPrint(
    desc: "byte_buffer_result_builder_html_response",
    benchmark: ByteBufferResultBuilderHTMLResponse(
        iterations: 100_000
    )
)

try measureAndPrint(
    desc: "byte_buffer_write_web_socket_header",
    benchmark: ByteBufferWriteWebSocketHeaderHandWritten(
        iterations: 100_000
    )
)

try measureAndPrint(
    desc: "byte_buffer_result_builder_web_socket_header",
    benchmark: ByteBufferWriteWebSocketHeaderResultBuilder(
        iterations: 100_000
    )
)
