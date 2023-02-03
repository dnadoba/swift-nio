//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

// ~4x faster

final class ByteBufferWriteStringHTMLResponse: Benchmark {
    private let iterations: Int
    private var buffer: ByteBuffer = .init()

    init(iterations: Int) {
        self.iterations = iterations
    }

    func setUp() throws {}

    func tearDown() {
        let expectedBuffer = ByteBuffer { HTMLResponse() }
        
        precondition(expectedBuffer == buffer)
    }

    func run() throws -> Int {
        var bytesWritten = 0
        for _ in 0..<self.iterations {
            buffer = ByteBuffer()
            HTMLResponse().write(to: &buffer)
            bytesWritten += buffer.readerIndex
        }
        
        return bytesWritten
    }
}

final class ByteBufferResultBuilderHTMLResponse: Benchmark {
    private let iterations: Int
    private var buffer: ByteBuffer = .init()

    init(iterations: Int) {
        self.iterations = iterations
    }

    func setUp() throws {}

    func tearDown() {
        var expectedBuffer = ByteBuffer()
        HTMLResponse().write(to: &expectedBuffer)
        precondition(expectedBuffer == buffer)
    }

    func run() throws -> Int {
        var bytesWritten = 0
        
        for _ in 0..<self.iterations {
            buffer = ByteBuffer()
            buffer.write { HTMLResponse() }
            bytesWritten += buffer.readerIndex
        }
        
        return bytesWritten
    }
}


fileprivate struct HTMLResponse: FixedSized {
    func write(to buffer: inout ByteBuffer) {
        buffer.writeString("HTTP/1.1 200 OK")
        buffer.writeString("\r\n")
        buffer.writeString("Connection")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("close")
        buffer.writeString("\r\n")
        buffer.writeString("Proxy-Connection")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("close")
        buffer.writeString("\r\n")
        buffer.writeString("Via")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("HTTP/1.1 localhost (IBM-PROXY-WTE)")
        buffer.writeString("\r\n")
        buffer.writeString("Date")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("Tue, 08 May 2018 13:42:56 GMT")
        buffer.writeString("\r\n")
        buffer.writeString("Server")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("Apache/2.2.15 (Red Hat)")
        buffer.writeString("\r\n")
        buffer.writeString("Strict-Transport-Security")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("max-age=15768000; includeSubDomains")
        buffer.writeString("\r\n")
        buffer.writeString("Last-Modified")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("Tue, 08 May 2018 13:39:13 GMT")
        buffer.writeString("\r\n")
        buffer.writeString("ETag")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("357031-1809-56bb1e96a6240")
        buffer.writeString("\r\n")
        buffer.writeString("Accept-Ranges")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("bytes")
        buffer.writeString("\r\n")
        buffer.writeString("Content-Length")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("6153")
        buffer.writeString("\r\n")
        buffer.writeString("Content-Type")
        buffer.writeString(":")
        buffer.writeString(" ")
        buffer.writeString("text/html; charset=UTF-8")
        buffer.writeString("\r\n")
        buffer.writeString("\r\n")
    }
    
    var writer: some FixedSized {
        "HTTP/1.1 200 OK"
        "\r\n"
        "Connection"
        ":"
        " "
        "close"
        "\r\n"
        "Proxy-Connection"
        ":"
        " "
        "close"
        "\r\n"
        "Via"
        ":"
        " "
        "HTTP/1.1 localhost (IBM-PROXY-WTE)"
        "\r\n"
        "Date"
        ":"
        " "
        "Tue, 08 May 2018 13:42:56 GMT"
        "\r\n"
        "Server"
        ":"
        " "
        "Apache/2.2.15 (Red Hat)"
        "\r\n"
        "Strict-Transport-Security"
        ":"
        " "
        "max-age=15768000; includeSubDomains"
        "\r\n"
        "Last-Modified"
        ":"
        " "
        "Tue, 08 May 2018 13:39:13 GMT"
        "\r\n"
        "ETag"
        ":"
        " "
        "357031-1809-56bb1e96a6240"
        "\r\n"
        "Accept-Ranges"
        ":"
        " "
        "bytes"
        "\r\n"
        "Content-Length"
        ":"
        " "
        "6153"
        "\r\n"
        "Content-Type"
        ":"
        " "
        "text/html; charset=UTF-8"
        "\r\n"
        "\r\n"
    }
}
