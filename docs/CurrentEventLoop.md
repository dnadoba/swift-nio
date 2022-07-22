# CurrentEventLoop

## Introduction



## Motivation

NIOs `ChannelPipeline` and other patterns which interact with the `ChannelPipeline` only ever run on one fixed `EventLoop`. NIO programms rely on these semantics for synchronisation. These sementics are not encoded in the type system. Every `NIO` user needs to know where an `EventLoop`, `EventLoopFuture` or `Scheduled` came from to know if it is safe to access shared state without addition synchronisation.

SwiftNIO has now fuly adopted Sendable. Therefore all escaping function types need to conform to `Sendable` for allmost all methods on `EventLoop`, `EventLoopFuture` and `Scheduled`. The function types need to conform to `Sendable` because they may not be executed on the current EventLoop.

Many NIO programms will now get false positive Sendable warnings in strict concurrency mode because of these new Sendable requirments. One good example with ~30 false positive Sendable warnings is `NIO`s own `NIOHTTP1Server` example. 

## Proposed solution

This PR includes a new collection of non-Sendable wrapper types:
```swift
public struct CurrentEventLoop {
    public let wrapped: EventLoop
    [...]
}
public struct EventLoopPromiseOnCurrentEventLoop<Value> {
    public let wrapped: EventLoopPromise<Value>
    [...]
}
public struct EventLoopFutureOnCurrentEventLoop<Value> {
    public let wrapped: EventLoopFuture<Value>
    [...]
}
public struct ScheduledOnCurrentEventLoop<T> {
    public let wrapped: Scheduled<T>
    [...]
}

```

Each type garantees that there associated `EventLoop` is the current EventLoop i.e. `EventLoop.inEventLoop == true`. 
A `CurrentEventLoop` can be consturcted from an EventLoop by calling `EventLoop.iKnowIAmOnThisEventLoop()`.
```swift
extension EventLoop {
    public func iKnowIAmOnThisEventLoop() -> CurrentEventLoop {
        self.preconditionInEventLoop()
        return .init(self)
    }
}
```
A precondition makes sure that this acutally the case at runtime. This check is only nesscary during creation of the wrapper. As these types are non-Sendable, the compiler makes sure that an instance is never passed to a different `EventLoop`. 

These types have almost the same interface as the types they wrap, but with one important difference: All methods take non-Sendable function types as arguments. This is safe as the functions passed to these methods are allways executed on the same `EventLoop` as the method is called on.

## Detailed design


## Source compatibility

In its current form, it is a purly addtive change. In the future, we may want to replace the `EventLoop` returned by `ChannelContext.eventLoop` with `CurrentEventLoop`.

