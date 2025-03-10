# AsyncExtensions


<p align="left">
<img src="https://github.com/AsyncCommunity/AsyncExtensions/actions/workflows/ci.yml/badge.svg?branch=main" alt="Build Status" title="Build Status">
<a href="https://codecov.io/gh/sideeffect-io/AsyncExtensions"><img src="https://codecov.io/gh/sideeffect-io/AsyncExtensions/branch/main/graph/badge.svg?token=NTGOIK6CSE"/></a>
<a href="https://github.com/apple/swift-package-manager" target="_blank"><img src="https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg" alt="AsyncExtensions supports Swift Package Manager (SPM)"></a>
<img src="https://img.shields.io/badge/platforms-iOS%2013%20%7C%20macOS 10.15%20%7C%20tvOS%2013%20%7C%20watchOS%206-333333.svg" />

**AsyncExtensions** provides a collection of operators that intends to ease the creation and combination of `AsyncSequences`.

**AsyncExtensions** can be seen as a companion to Apple [swift-async-algorithms](https://github.com/apple/swift-async-algorithms), which provides operators that the community needs and are not provided by Apple.

## Adding AsyncExtensions as a Dependency

To use the `AsyncExtensions` library in a SwiftPM project, 
add the following line to the dependencies in your `Package.swift` file:

```swift
.package(url: "https://github.com/sideeffect-io/AsyncExtensions"),
```

Include `"AsyncExtensions"` as a dependency for your executable target:

```swift
.target(name: "<target>", dependencies: ["AsyncExtensions"]),
```

Finally, add `import AsyncExtensions` to your source code.

## Features

### Channels
* [AsyncBufferedChannel](./Sources/AsyncChannels/AsyncBufferedChannel.swift): Buffered communication channel between tasks. The elements are not shared and will be spread across consumers (same as 
AsyncStream)
* [AsyncThrowingBufferedChannel](./Sources/AsyncChannels/AsyncThrowingBufferedChannel.swift): Throwing buffered communication channel between tasks

### Subjects
* [AsyncPassthroughSubject](./Sources/AsyncSubjects/AsyncPassthroughSubject.swift): Subject with a shared output
* [AsyncThrowingPassthroughSubject](./Sources/AsyncSubjects/AsyncThrowingPassthroughSubject.swift): Throwing subject with a shared output
* [AsyncCurrentValueSubject](./Sources/AsyncSubjects/AsyncCurrentValueSubject.swift): Subject with a shared output. Maintain an replays its current value
* [AsyncThrowingCurrentValueSubject](./Sources/AsyncSubjects/AsyncThrowingCurrentValueSubject.swift): Throwing subject with a shared output. Maintain an replays its current value
* [AsyncReplaySubject](./Sources/AsyncSubjects/AsyncReplaySubject.swift): Subject with a shared output. Maintain an replays a buffered amount of values
* [AsyncThrowingReplaySubject](./Sources/AsyncSubjects/AsyncThrowingReplaySubject.swift): Throwing subject with a shared output. Maintain an replays a buffered amount of values

### Combiners
* [`merge(_:)`](./Sources/Combiners/Merge/AsyncMergeSequence.swift): Merges any `AsyncSequence` into an AsyncSequence of elements
* [`withLatest(_:)`](./Sources/Combiners/WithLatestFrom/AsyncWithLatestFromSequence.swift): Combines elements from self with the last known element from an other `AsyncSequence`
* [`withLatest(_:_:)`](./Sources/Combiners/WithLatestFrom/AsyncWithLatestFrom2Sequence.swift): Combines elements from self with the last known elements from two other async sequences

### Creators
* [AsyncEmptySequence](./Sources/Creators/AsyncEmptySequence.swift): Creates an `AsyncSequence` that immediately finishes
* [AsyncFailSequence](./Sources/Creators/AsyncFailSequence.swift): Creates an `AsyncSequence` that immediately fails
* [AsyncJustSequence](./Sources/Creators/AsyncJustSequence.swift): Creates an `AsyncSequence` that emits an element an finishes
* [AsyncThrowingJustSequence](./Sources/Creators/AsyncThrowingJustSequence.swift): Creates an `AsyncSequence` that emits an elements and finishes bases on a throwing closure
* [AsyncTimerSequence](./Sources/Creators/AsyncTimerSequence.swift): Creates an `AsyncSequence` that emits a date value periodically
* [AsyncStream Pipe](./Sources/Creators/AsyncStream+Pipe.swift): Creates an AsyncStream and returns a tuple standing for its inputs and outputs

### Operators
* [`handleEvents()`](./Sources/Operators/AsyncHandleEventsSequence.swift): Executes closures during the lifecycle of the self
* [`mapToResult()`](./Sources/Operators/AsyncMapToResultSequence.swift): Maps elements and failure from self to a `Result` type
* [`prepend(_:)`](./Sources/Operators/AsyncPrependSequence.swift): Prepends an element to self
* [`scan(_:_:)`](./Sources/Operators/AsyncScanSequence.swift): Transforms elements from self by providing the current element to a closure along with the last value returned by the closure
* [`assign(_:)`](./Sources/Operators/AsyncSequence+Assign.swift): Assigns elements from self to a property
* [`collect(_:)`](./Sources/Operators/AsyncSequence+Collect.swift): Iterate over elements from self and execute a closure
* [`eraseToAnyAsyncSequence()`](./Sources/Operators/AsyncSequence+EraseToAnyAsyncSequence.swift): Erases to AnyAsyncSequence
* [`flatMapLatest(_:)`](./Sources/Operators/AsyncSequence+FlatMapLatest.swift): Transforms elements from self into a `AsyncSequence` and republishes elements sent by the most recently received `AsyncSequence` when self is an `AsyncSequence` of `AsyncSequence`
* [`multicast(_:)`](./Sources/Operators/AsyncMulticastSequence.swift): Shares values from self to several consumers thanks to a provided Subject
* [`share()`](./Sources/Operators/AsyncSequence+Share.swift): Shares values from self to several consumers
* [`switchToLatest()`](./Sources/Operators/AsyncSwitchToLatestSequence.swift): Republishes elements sent by the most recently received `AsyncSequence` when self is an `AsyncSequence` of `AsyncSequence`

More operators and extensions are to come. Pull requests are of course welcome.
