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

import XCTest
@_spi(AsyncChannel) import NIOCore
@_spi(AsyncChannel) import NIOPosix
import Dispatch
@testable import NIOHTTP1

final class HTTPAsyncChannelTests: XCTestCase {
    @available(macOS 14, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    func testAsyncChannel() async throws {
        var expectedHeaders = HTTPHeaders()
        expectedHeaders.add(name: "connection", value: "keep-alive")
        
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let serverChannel = try await ServerBootstrap(group: eventLoopGroup)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.autoRead, value: true)
            .bind(
                host: "127.0.0.1",
                port: 0,
                childChannelInitializer: { channel in
                    channel.pipeline.configureHTTPServerPipeline().flatMap {
                        channel.pipeline.addHandler(UseByteBufferInsteadOfIODataInHTTPResponsePart())
                    }.flatMapThrowing {
                        try NIOAsyncChannel(
                            synchronouslyWrapping: channel,
                            configuration: .init(
                                inboundType: HTTPServerRequestPart.self,
                                outboundType: HTTPPart<HTTPResponseHead, ByteBuffer>.self
                            )
                        )
                    }
                }
            )
        
        @Sendable
        func executeIncompleteRequestWithNewConnection(to address: SocketAddress) throws {
            let clientChannel = try assertNoThrowWithValue(ClientBootstrap(group: eventLoopGroup)
                .channelInitializer { channel in
                    channel.pipeline.addHTTPClientHandlers()
                }
                .connect(to: address)
                .wait())
            defer {
                XCTAssertNoThrow(try clientChannel.syncCloseAcceptingAlreadyClosed())
            }
            var head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/204")
            head.headers.add(name: "Host", value: "apple.com")
            clientChannel.write(NIOAny(HTTPClientRequestPart.head(head)), promise: nil)
            try clientChannel.writeAndFlush(NIOAny(HTTPClientRequestPart.body(.byteBuffer(ByteBuffer(string: "Hello World from request"))))).wait()
            // we are missing the end
        }
        
        DispatchQueue.global().async {
            do {
                try executeIncompleteRequestWithNewConnection(to: serverChannel.channel.localAddress!)
                try executeIncompleteRequestWithNewConnection(to: serverChannel.channel.localAddress!)
            } catch {
                XCTFail("\(error)")
            }
        }
        
        try await withThrowingDiscardingTaskGroup { group in
            for try await connection in serverChannel.inboundStream {
                print("new request")
                group.addTask {
                    try await withThrowingDiscardingTaskGroup { group in
                        group.addTask {
                            //for try await _ in reamingHTTPParts {}
                            try await connection.outboundWriter.write(.head(.init(version: .http1_1, status: .ok)))
                            try await connection.outboundWriter.write(.body(ByteBuffer(string: "Hello World")))
                            try await connection.outboundWriter.write(.end(nil))
                        }
                        
                        group.addTask {
                            print("consuming full request")
                            for try await _ in connection.inboundStream {}
                            print("request consumed")
                        }
                    }
                    print("request done")
                }
            }
        }
    }
}

final class UseByteBufferInsteadOfIODataInHTTPResponsePart: ChannelOutboundHandler {
    typealias OutboundIn = HTTPPart<HTTPResponseHead, ByteBuffer>
    typealias OutboundOut = HTTPServerResponsePart
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let requestPartIn = self.unwrapOutboundIn(data)
        
        let requestPartOut: OutboundOut = {
            switch requestPartIn {
            case .head(let head): return .head(head)
            case .body(let byteBuffer): return .body(.byteBuffer(byteBuffer))
            case .end(let headers): return .end(headers)
            }
        }()
        
        context.write(self.wrapOutboundOut(requestPartOut), promise: promise)
    }
}
