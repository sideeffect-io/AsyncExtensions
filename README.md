# AsyncExtensions


<p align="left">
<img src="https://github.com/AsyncCommunity/AsyncExtensions/actions/workflows/ci.yml/badge.svg?branch=main" alt="Build Status" title="Build Status">
<a href="https://codecov.io/gh/AsyncCommunity/AsyncExtensions"><img src="https://codecov.io/gh/AsyncCommunity/AsyncExtensions/branch/main/graph/badge.svg?token=NTGOIK6CSE"/></a>
<a href="https://github.com/apple/swift-package-manager" target="_blank"><img src="https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg" alt="CombineExt supports Swift Package Manager (SPM)"></a>
<img src="https://img.shields.io/badge/platforms-iOS%2013%20%7C%20macOS 10.15%20%7C%20tvOS%2013%20%7C%20watchOS%206-333333.svg" />

AsyncExtensions provides a collection of operators, async sequences and async streams that mimics Combine behaviour.

The purpose is to be able to chain operators, just as you would do with any reactive programming framework:

```swift
AsyncSequences
    .Merge(sequence1, sequence2, sequence3)
    .prepend(0)
    .handleEvents(onElement: { print($0) }, onFinish: { print("Finished") })
    .scan("") { accumulator, element in accumulator + "\(element)" }
    .collect { print($0) }
```

### Async Sequences
* [Just](#Just)
* [Empty](#Empty)
* [Fail](#Fail)
* [From](#From)
* [Merge](#Merge)
* [Zip2](#Zip2)
* [Zip3](#Zip3)
* [Zip](#Zip)

### Async Streams
* [Passthrough](#Passthrough)
* [CurrentValue](#CurrentValue)
* [Replay](#Replay)

### Operators
* [Collect](#Collect)
* [Scan](#Scan)
* [SwitchToLatest](#SwitchToLatest)
* [FlatMapLatest](#FlatMapLatest)
* [HandleEvents](#HandleEvents)
* [Assign](#Assign)
* [EraseToAnyAsyncSequence](#EraseToAnyAsyncSequence)

More operators and extensions are to come. Pull requests are of course welcome.

## Async Sequences

### Just

`Just` is an AsyncSequence that outputs a single value and finishes.

```swift
let justSequence = AsyncSequences.Just<Int>(1)
for try await element in justSequence {
    // will be called once with element = 1
}
```

### Empty

`Empty` is an AsyncSequence that immediately finishes without emitting values.

```swift
let emptySequence = AsyncSequences.Empty<Int>()
for try await element in emptySequence {
    // will never be called
}
```

### Fail

`Fail` is an AsyncSequence that outputs no elements and throws an error.

```swift
let failSequence = AsyncSequences.Fail<Int, Swift.Error>(error: NSError(domain: "", code: 1))
do {
    for try await element in failSequence {
        // will never be called
    }
} catch {
    // will catch `NSError(domain: "", code: 1)` here
}
```

### From

`From` is an AsyncSequence that outputs elements from a traditional Sequence.

```swift
let fromSequence = AsyncSequences.From([1, 2, 3, 4, 5])

for await element in fromSequence {
    print(element) // will print 1 2 3 4 5
}
```

A variation offers to set an interval of time between each element.

```swift
let fromSequence = AsyncSequences.From([1, 2, 3, 4, 5], interval: .milliSeconds(10))

for await element in fromSequence {
    print(element) // will print 1 2 3 4 5 with an interval of 10ms between elements
}
```

### Merge

`Merge` is an AsyncSequence that merges several async sequences respecting their temporality while being iterated over.
When all the async sequences have finished, so too does the merged async sequence.
If an async sequence fails, so too does the merged async sequence.

```swift
// 0.1ms   1ms    1.5ms   2ms     3ms     4.5ms
//  4       1       5      2       3        6

let asyncSequence1 = AsyncStream(Int.self, bufferingPolicy: .unbounded) { continuation in
    Task {
        try await Task.sleep(nanoseconds: 1_000_000)
        continuation.yield(1)
        try await Task.sleep(nanoseconds: 1_000_000)
        continuation.yield(2)
        try await Task.sleep(nanoseconds: 1_000_000)
        continuation.yield(3)
        continuation.finish()
    }
}

let asyncSequence2 = AsyncStream(Int.self, bufferingPolicy: .unbounded) { continuation in
    Task {
        try await Task.sleep(nanoseconds: 100_000)
        continuation.yield(4)
        try await Task.sleep(nanoseconds: 1_400_000)
        continuation.yield(5)
        try await Task.sleep(nanoseconds: 3_000_000)
        continuation.yield(6)
        continuation.finish()
    }
}

let mergedAsyncSequence = AsyncSequences.Merge(asyncSequence1, asyncSequence2)

for try await element in mergedAsyncSequence {
    print(element) // will print -> 4 1 5 2 3 6
}
```

### Zip2

`Zip2` is an AsyncSequence that combines the latest elements from two sequences according to their temporality and emits a tuple to the client.
If any async sequence ends successfully or fails with an error, so too does the zipped async Sequence.

```swift
let asyncSequence1 = AsyncSequences.From([1, 2, 3, 4, 5])
let asyncSequence2 = AsyncSequences.From(["5", "4", "3", "2", "1"])

let zippedAsyncSequence = AsyncSequences.Zip2(asyncSequence1, asyncSequence2)

for try await element in zippedAsyncSequence {
    print(element) // will print -> (1, "5") (2, "4") (3, "3") (4, "2") (5, "1")
}
```

### Zip3

`Zip3` is an AsyncSequence that combines the latest elements from two sequences according to their temporality and emits a tuple to the client.
If any async sequence ends successfully or fails with an error, so too does the zipped async Sequence.

```swift
let asyncSequence1 = AsyncSequences.From([1, 2, 3, 4, 5])
let asyncSequence2 = AsyncSequences.From(["5", "4", "3", "2", "1"])
let asyncSequence3 = AsyncSequences.From([true, false, true, false, true])

let zippedAsyncSequence = AsyncSequences.Zip3(asyncSequence1, asyncSequence2, asyncSequence3)

for try await element in zippedAsyncSequence {
    print(element) // will print -> (1, "5", true) (2, "4", false) (3, "3", true) (4, "2", false) (5, "1", true)
}
```

### Zip

`Zip` is an AsyncSequence that combines the latest elements from several sequences according to their temporality and emits an array to the client.
If any async sequence ends successfully or fails with an error, so too does the zipped async Sequence.

```swift
let asyncSequence1 = AsyncSequences.From([1, 2, 3])
let asyncSequence2 = AsyncSequences.From([1, 2, 3])
let asyncSequence3 = AsyncSequences.From([1, 2, 3])
let asyncSequence4 = AsyncSequences.From([1, 2, 3])
let asyncSequence5 = AsyncSequences.From([1, 2, 3])

let zippedAsyncSequence = AsyncSequences.Zip(asyncSequence1, asyncSequence2, asyncSequence3, asyncSequence4, asyncSequence5)

for try await element in zippedAsyncSequence {
    print(element) // will print -> [1, 1, 1, 1, 1] [2, 2, 2, 2, 2] [3, 3, 3, 3, 3]
}
```

## Async Streams

### Passthrough

`Passthrough` is an async sequence in which one can send values over time.

```swift
let passthrough = AsyncStreams.Passthrough<Int>()

Task {
    for try await element in passthrough {
        print(element) // will print 1 2
    }
}

Task {
    for try await element in passthrough {
        print(element) // will print 1 2
    }
}

.. later in the application flow

passthrough.send(1)
passthrough.send(2)
```

### CurrentValue

`CurrentValue` is an async sequence in which one can send values over time.
The current value is always accessible as an instance variable.
The current value is replayed for any new async loop.

```swift
let currentValue = AsyncStreams.CurrentValue<Int>(1)

Task {
    for try await element in passthrough {
        print(element) // will print 1 2
    }
}

Task {
    for try await element in passthrough {
        print(element) // will print 1 2
    }
}

.. later in the application flow

currentValue.send(2)

print(currentValue.element) // will print 2
```

### Replay

`Replay`is an async sequence in which one can send values over time.
Values are buffered in a FIFO fashion so they can be iterated over by new loops.
When the `bufferSize` is outreached the oldest value is dropped.

```swift
let replay = AsyncStreams.Replay<Int>(bufferSize: 3)

(1...5).forEach { replay.send($0) }

for try await element in replay {
    print(element) // will print 3, 4, 5
}
```

## Operators

### Collect

`collect(_:)` iterates over each element of the AsyncSequence and give it to the async block.

```swift
let fromSequence = AsyncSequences.From([1, 2, 3])
fromSequence
    .collect { print($0) } // will print 1 2 3
```

### Scan

`scan(_:_:)` transforms elements from the upstream async sequence by providing the current element to a closure along with the last value returned by the closure. Each intermediate value will be emitted in the downstream async sequence.

```swift
let sourceSequence = AsyncSequences.From([1, 2, 3, 4, 5])
let scannedSequence = sourceSequence.scan("") { accumulator, element in accumulator + "\(element)"}

for try await element in scannedSequence {
    print(element)
}

// will print:
1
12
123
1234
12345
```

### SwitchToLatest

`switchToLatest()` re-emits elements sent by the most recently received async sequence. This operator applies only in the case where the upstream async sequence's `Element` is it-self an async sequence.

```
let sourceSequence = AsyncSequences.From([1, 2, 3])
let mappedSequence = sourceSequence.map { element in
	AsyncSequences.From(["a\(element)", "b\(element)"])
}
let switchedSequence = mappedSequence.switchToLatest()

for try await element in switchedSequence {
    print(element) // will print a3 b3
}
```

### FlatMapLatest

`flatMapLatest(_:)` transforms the upstream async sequence elements into an async sequence and flattens the sequence of events from these multiple sources async sequences to appear as if they were coming from a single async sequence of events. Mapping to a new async sequence will cancel the task related to the previous one.

This operator is basically a shortcut for `map()` and `switchToLatest()`.

```swift
let sourceSequence = AsyncSequences.From([1, 2, 3])
let flatMapLatestSequence = sourceSequence.flatMapLatest { element in
	AsyncSequences.From(["a\(element)", "b\(element)"])
}

for try await element in flatMapLatestSequence {
    print(element) // will print a3 b3
}
```

### Prepend

`prepend(_:)` prepends an element to the upstream async sequence.

```swift
let sourceSequence = AsyncSequences.From([1, 2, 3])
let prependSequence = sourceSequence.prepend(0)

for try await element in prependSequence {
    print(element) // will print 0 1 2 3
}
```

### HandleEvents

`handleEvents(onStart:onElement:onCancel:onFinish)` performs the specified closures when async sequences events occur.

```swift
let sourceSequence = AsyncSequences.From([1, 2, 3, 4, 5])
let handledSequence = sourceSequence.handleEvents {
   print("Begin iterating")
} onElement: { element in
   print("Element is \(element)")
} onCancel: {
   print("Cancelled")
} onFinish: { termination in
   print(termination)
}

for try await element in handledSequence {}

// will print:
// Begin iterating
// Element is 1
// Element is 2
// Element is 3
// Element is 4
// Element is 5
// finished
```

### Assign

`assign(to:on:)` assigns each element from the async sequence to a property on an object.

```swift
class Root {
    var property: String = ""
}

let root = Root()
let fromSequence = AsyncSequences.From(["1", "2", "3"])
try await fromSequence.assign(to: \.property, on: root) // will set the property value to "1", "2", "3"
```

### EraseToAnyAsyncSequence

`eraseToAnyAsyncSequence()` type-erases the async sequence into an AnyAsyncSequence.
