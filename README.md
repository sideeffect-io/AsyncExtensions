# AsyncExtensions

[![Build status](https://github.com/sideeffect-io/AsyncExtensions/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/sideeffect-io/AsyncExtensions/actions/workflows/ci.yml)
[![Code coverage](https://codecov.io/gh/sideeffect-io/AsyncExtensions/branch/main/graph/badge.svg)](https://codecov.io/gh/sideeffect-io/AsyncExtensions)

AsyncExtensions adds operators, subjects, and buffered channels to Swift's `AsyncSequence`. Use it to build streams of values, combine them, and share them between tasks.

An async sequence produces values over time. You read those values with `for await`, or `for try await` when the sequence can throw. Operators let you change how those values are produced or consumed.

- [Installation](#installation)
- [A first example](#a-first-example)
- [Creating sequences](#creating-sequences)
- [Transforming and consuming values](#transforming-and-consuming-values)
- [Combining sequences](#combining-sequences)
- [Sending values with channels and subjects](#sending-values-with-channels-and-subjects)
- [Sharing a sequence](#sharing-a-sequence)
- [Managing observation tasks](#managing-observation-tasks)
- [Using Swift Async Algorithms](#using-swift-async-algorithms)

## Installation

The package requires a Swift 6.1 or later compiler and uses Swift 5 language mode. It supports Linux and iOS 18, macOS 15, tvOS 18, and watchOS 11 or later. Its shared-state synchronization uses `Synchronization.Mutex` on every platform.

### In Xcode

1. Open your project and choose **File > Add Package Dependencies**.
2. Enter `https://github.com/sideeffect-io/AsyncExtensions.git` in the search field.
3. Choose **Up to Next Major Version**, starting at **0.6.0**, and add the package.
4. Select the **AsyncExtensions** library product and add it to your app target.

Add `import AsyncExtensions` to the Swift files that use the library. See Apple's [package installation guide](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) for the Xcode workflow.

### In a Swift package

Add the package to `dependencies`, then add its library product to the target that uses it. For example, a command-line app can use this `Package.swift`:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(
            url: "https://github.com/sideeffect-io/AsyncExtensions.git",
            from: "0.6.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [
                .product(name: "AsyncExtensions", package: "AsyncExtensions")
            ]
        )
    ]
)
```

Put your app's code in `Sources/MyApp/main.swift`, import `AsyncExtensions`, and run it with `swift run`. For a library target, add the same product dependency to your existing `.target(...)`. SwiftPM's [package manifest reference](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html) describes these dependency declarations.

### On Linux

Install a [Swift toolchain for Linux](https://www.swift.org/install/linux/), then build and test this package with:

```sh
swift build -c release
swift test
```

Linux CI runs the full test suite on Ubuntu 22.04 with Swift 6.1.3 and 6.4.0. The Apple deployment versions in `Package.swift` do not restrict Linux builds.

## A first example

This sequence produces three numbers. `scan` keeps a running total, and the loop prints each total as it arrives:

```swift
import AsyncExtensions

let numbers = AsyncLazySequence([1, 2, 3])
let runningTotals = numbers.scan(0) { total, number in
    total + number
}

for await total in runningTotals {
    print(total)
}
// Prints: 1, 3, 6
```

The examples below assume `import AsyncExtensions` and an async context, such as an `async` function, a `Task`, or a command-line app's `main.swift`. Each example is independent.

## Creating sequences

### `AsyncLazySequence`: start with an array or another synchronous sequence

Wrap any `Sequence` to read its elements with an async loop. It preserves the input's order and finishes when the input runs out.

```swift
let names = AsyncLazySequence(["Alice", "Bob", "Charlie"])

for await name in names {
    print(name)
}
// Prints: Alice, Bob, Charlie
```

### `AsyncJustSequence`: produce one value

Use this when an API expects an async sequence but you have only one value to send. Passing `nil` creates a sequence with no elements.

```swift
let greeting = AsyncJustSequence("Hello")

for await message in greeting {
    print(message)
}
// Prints: Hello
```

The `factory:` initializer delays creating the value until iteration begins. The async factory runs once per independent iterator. Returning `nil` finishes without a value.

```swift
let greeting = AsyncJustSequence<String>(factory: {
    "Hello" // Create or fetch the value here when it is needed.
})

print(await greeting.collect())
// Prints: ["Hello"]
```

Cancellation before the first value is requested skips the factory. If cancellation happens while the factory is running, its eventual value is discarded.

### `AsyncThrowingJustSequence`: produce one value from work that can fail

The factory runs on the first request for a value. It can return one element, return `nil`, or throw an error.

```swift
enum InputError: Error {
    case invalidNumber
}

let number = AsyncThrowingJustSequence<Int>(factory: {
    guard let value = Int("42") else {
        throw InputError.invalidNumber
    }
    return value
})

for try await value in number {
    print(value)
}
// Prints: 42
```

There is also a value initializer, such as `AsyncThrowingJustSequence(42)`, for code that needs a throwing sequence type without a factory.

### `AsyncEmptySequence`: finish without a value

Use an empty sequence when there is nothing to produce. Specify its element type so it can fit into the rest of your pipeline.

```swift
let empty = AsyncEmptySequence<String>()
let messages = await empty.collect()

print(messages)
// Prints: []
```

### `AsyncFailSequence`: fail without a value

Use a failing sequence to represent an error through an async sequence API.

```swift
enum DownloadError: Error {
    case unavailable
}

let download = AsyncFailSequence<String>(DownloadError.unavailable)

do {
    for try await message in download {
        print(message)
    }
} catch {
    print("Download failed: \(error)")
}
// Prints: Download failed: unavailable
```

### `AsyncBufferedTimerSequence`: produce dates at regular intervals

The timer emits a `Date` immediately, then approximately once per interval. Each iterator starts its own timer. Dates are buffered if the consumer is slower than the timer.

```swift
import Foundation

let timer = AsyncBufferedTimerSequence(every: .seconds(1))
let observation = Task {
    for await date in timer {
        print("Tick: \(date)")
    }
}

// Keep the timer running for this example's two-second observation window.
try await Task.sleep(nanoseconds: 2_000_000_000)
observation.cancel()
await observation.value
```

You can also set the producer's task priority with `AsyncBufferedTimerSequence(priority: .background, every: .seconds(1))`. Cancel the observation task when you stop using the timer. Exiting a loop with `break` alone does not cancel its timer task.

### `AsyncStream.pipe()` and `AsyncThrowingStream.pipe()`: get both ends of a stream

`pipe()` returns `(continuation, stream)`. Send values through the continuation and read them from the stream. Values sent before iteration are buffered according to the chosen policy; the default is `.unbounded`.

```swift
let (input, messages) = AsyncStream<String>.pipe()

input.yield("Hello")
input.yield("Goodbye")
input.finish()

for await message in messages {
    print(message)
}
// Prints: Hello, Goodbye
```

For a stream that can fail, finish its continuation with an error:

```swift
enum ConnectionError: Error {
    case disconnected
}

let (input, messages) = AsyncThrowingStream<String, Error>.pipe()
input.yield("Connected")
input.finish(throwing: ConnectionError.disconnected)

do {
    for try await message in messages {
        print(message)
    }
} catch {
    print("Connection ended: \(error)")
}
// Prints: Connected, then Connection ended: disconnected
```

Pass `bufferingPolicy: .bufferingNewest(10)` to either factory to retain only the ten newest waiting values, or `.bufferingOldest(10)` to keep the ten oldest. These streams do not broadcast each value to every consumer; use [subjects](#subjects) or [sharing](#sharing-a-sequence) for that.

## Transforming and consuming values

| Operator | Use it to |
| --- | --- |
| [`prepend(_:)`](#prepend-start-with-an-initial-value) | Emit an initial value before the source's values. |
| [`scan(_:_:)`](#scan-keep-a-running-result) | Calculate a result after each input. |
| [`handleEvents(...)`](#handleevents-observe-a-pipelines-lifecycle) | Add logging or other side effects. |
| [`mapToResult()`](#maptoresult-read-errors-as-values) | Turn values and thrown errors into `Result` elements. |
| [`collect()` / `collect(_:)`](#collect-consume-the-sequence) | Gather all values or handle each one in a closure. |
| [`assign(to:on:)`](#assigntoon-update-an-objects-property) | Write each value to an object's property. |
| [`eraseToAnyAsyncSequence()`](#erasetoanyasyncsequence-hide-the-concrete-sequence-type) | Expose a sequence through a common type. |
| [`flatMapLatest(_:)`](#flatmaplatest-replace-work-when-a-new-input-arrives) | Switch to the work for the latest input. |
| [`switchToLatest()`](#switchtolatest-follow-the-latest-inner-sequence) | Read from the latest sequence in a sequence of sequences. |

### `prepend`: start with an initial value

`prepend(_:)` emits your value first, then continues with the source. This is useful for an initial display value before updates arrive.

```swift
let updates = AsyncLazySequence(["Loading", "Ready"])
let statuses = updates.prepend("Idle")

for try await status in statuses {
    print(status)
}
// Prints: Idle, Loading, Ready
```

The returned sequence requires `try` even when its source is nonthrowing.

### `scan`: keep a running result

`scan(_:_:)` passes the previous result and the next element to your closure. It emits each new result. The initial result is the starting accumulator; it is not emitted on its own.

```swift
let deposits = AsyncLazySequence([10, 20, 5])
let balances = deposits.scan(0) { balance, deposit in
    balance + deposit
}

print(await balances.collect())
// Prints: [10, 30, 35]
```

The closure can perform async work. Errors from a throwing source propagate to the consumer.

### `handleEvents`: observe a pipeline's lifecycle

Add callbacks without changing the elements. Each callback is optional and can perform async work.

```swift
let numbers = AsyncLazySequence([1, 2]).handleEvents(
    onStart: {
        print("Started")
    },
    onElement: { number in
        print("Received \(number)")
    },
    onCancel: {
        print("Cancelled")
    },
    onFinish: { termination in
        switch termination {
        case .finished:
            print("Finished")
        case .failure(let error):
            print("Failed: \(error)")
        }
    }
)

await numbers.collect { _ in }
// Prints: Started, Received 1, Received 2, Finished
```

`onStart` runs when the iterator first requests a value. `onElement` runs before that value reaches the consumer. Normal completion and errors call `onFinish`; cancellation calls `onCancel`. An early `break` does not request the end of the sequence, so it does not trigger `onFinish`.

### `mapToResult`: read errors as values

`mapToResult()` turns each element into `.success(value)` and a thrown error into `.failure(error)`. Its output sequence does not throw.

```swift
enum DownloadError: Error {
    case unavailable
}

let download = AsyncFailSequence<String>(DownloadError.unavailable)

for await result in download.mapToResult() {
    switch result {
    case .success(let message):
        print(message)
    case .failure(let error):
        print("Download failed: \(error)")
    }
}
// Prints: Download failed: unavailable
```

This changes how you receive an error; it does not retry or restart the source. If you want to handle the error and stop reading, exit the loop in the `.failure` case.

### `collect`: consume the sequence

`collect()` waits for completion and returns all elements in an array:

```swift
let numbers = AsyncLazySequence([1, 2, 3])
let values = await numbers.collect()

print(values)
// Prints: [1, 2, 3]
```

`collect(_:)` calls an async closure for each element and returns when the sequence ends:

```swift
let names = AsyncLazySequence(["Alice", "Bob"])

await names.collect { name in
    print("Hello, \(name)")
}
// Prints: Hello, Alice; Hello, Bob
```

Use `try await` if the source or your closure can throw. The array overload keeps every element in memory and cannot return while a sequence remains open, so use it for finite sequences.

### `assign(to:on:)`: update an object's property

`assign` consumes the sequence and writes each element to the property identified by a writable key path.

```swift
final class Download {
    var progress: Int = 0
}

let download = Download()
let progressUpdates = AsyncLazySequence([25, 50, 100])

try await progressUpdates.assign(to: \.progress, on: download)
print(download.progress)
// Prints: 100
```

This method requires `try await` and returns when the sequence ends. It does not select an actor or dispatch updates to the main thread. For UI state, make sure your observation and property mutation use the UI's required isolation.

### `eraseToAnyAsyncSequence`: hide the concrete sequence type

Use type erasure when you want to return different sequence implementations through one API. The source must be `Sendable`.

```swift
func greetingMessages(isSignedIn: Bool) -> AnyAsyncSequence<String> {
    if isSignedIn {
        return AsyncJustSequence("Welcome back").eraseToAnyAsyncSequence()
    }
    return AsyncEmptySequence<String>().eraseToAnyAsyncSequence()
}

for try await message in greetingMessages(isSignedIn: true) {
    print(message)
}
// Prints: Welcome back
```

`AnyAsyncSequence` has a throwing iterator, so use `try` even if the original sequence was nonthrowing. You can also construct it directly with `AnyAsyncSequence(source)`.

### `flatMapLatest`: replace work when a new input arrives

Use `flatMapLatest(_:)` when an old operation becomes irrelevant as soon as a new input arrives, such as fetching results for a changing search query.

A transform can return a single value:

```swift
let number = AsyncJustSequence(21)
let doubled = number.flatMapLatest { value async -> Int in
    value * 2
}

for await value in doubled {
    print(value)
}
// Prints: 42
```

For single-value async work, each new input cancels the previous transformation and discards its late result. Cancellation is cooperative: the work itself must observe cancellation to stop promptly. A nonthrowing source and transform need no `try`. Returning a `Result.failure` is an ordinary value and allows later inputs to be processed.

A transform can also return another async sequence:

```swift
let queries = AsyncLazySequence(["swift", "swift concurrency"])
let suggestions = queries.flatMapLatest { query in
    AsyncLazySequence([
        "Read about \(query)",
        "Try an example of \(query)"
    ])
}

for await suggestion in suggestions {
    print(suggestion)
}
```

This form switches to each newly returned sequence and cancels consumption of the previous one. Some earlier suggestions may already have been delivered before the switch; their exact number depends on timing. Put cancellable work inside the returned sequence when you want that work to be replaced. The closure that creates a sequence is awaited before switching.

Both forms accept throwing transforms. Use `for try await` or `try await collect()` when the source, transform, or selected inner sequence can throw; those errors propagate to the consumer.

### `switchToLatest`: follow the latest inner sequence

Use `switchToLatest()` when your source already produces async sequences. Each new inner sequence replaces the previous one. It is the switching step used by `flatMapLatest`.

```swift
let playlists = AsyncLazySequence([
    AsyncLazySequence(["Track A", "Track B"]),
    AsyncLazySequence(["Track C", "Track D"])
])

for await track in playlists.switchToLatest() {
    print(track)
}
```

Tracks from the first playlist may arrive before the second playlist replaces it. The latest playlist continues after the outer sequence finishes. Cancelling the consuming task stops observation of both the outer sequence and the selected inner sequence.

## Combining sequences

### `zip`: pair elements by position

`AsyncExtensions.zip(...)` takes one element from each input and emits an array in input order. It finishes when an input runs out and propagates input errors.

```swift
let first = AsyncLazySequence([1, 2])
let second = AsyncLazySequence([10, 20])
let third = AsyncLazySequence([100, 200])
let fourth = AsyncLazySequence([1000, 2000])

for await row in AsyncExtensions.zip(first, second, third, fourth) {
    print(row)
}
// Prints: [1, 10, 100, 1000], then [2, 20, 200, 2000]
```

Inputs must have the same concrete sequence type, and both the sequences and their elements must be `Sendable`. When the element type is the same but the sequence types differ, erase each input to `AnyAsyncSequence` first. The output will then require `try`.

### `merge`: read values from whichever input is ready

`AsyncExtensions.merge(...)` emits each input's values as they become available. It preserves each input's order, but the order between inputs depends on timing. It finishes after all inputs finish; an input error fails the merge.

```swift
let first = AsyncLazySequence([1, 2])
let second = AsyncLazySequence([10, 20])
let third = AsyncLazySequence([100, 200])
let fourth = AsyncLazySequence([1000, 2000])

let values = await AsyncExtensions.merge(first, second, third, fourth).collect()
print(values.sorted())
// Prints: [1, 2, 10, 20, 100, 200, 1000, 2000]
```

The sorting is only to make this example's output predictable. The merge itself does not sort. As with variadic `zip`, all inputs must have the same concrete sequence type. Use `eraseToAnyAsyncSequence()` to combine different implementations with the same element type. For an array of inputs, use `AsyncMergeSequence(inputs)`.

### `withLatest(from:)`: sample another sequence when the source emits

Only the source drives output. Each source element is paired with the most recently observed value from the other sequence. Updates from the other sequence do not emit a pair on their own.

This example samples a connection status once per second:

```swift
let ticks = AsyncBufferedTimerSequence(every: .seconds(1))
let status = AsyncCurrentValueSubject("Online")
let samples = ticks.withLatest(from: status)

let observation = Task {
    for await (date, currentStatus) in samples {
        print("\(date): \(currentStatus)")
    }
}

try await Task.sleep(nanoseconds: 2_000_000_000)
observation.cancel()
await observation.value
```

Source elements are skipped until the other sequence's first value has been observed. The other sequence is consumed in a separate task, so the initial tick may be skipped. Sending a value to `status` and immediately sending a source event does not guarantee the pair includes that new status. Use `zip` when every element must be paired by position.

### `withLatest(from:_:)`: sample two other sequences

This overload emits `(sourceElement, latestFirstValue, latestSecondValue)`. It starts producing output once both other sequences have supplied a value.

```swift
let ticks = AsyncBufferedTimerSequence(every: .seconds(1))
let status = AsyncCurrentValueSubject("Online")
let battery = AsyncCurrentValueSubject(80)
let samples = ticks.withLatest(from: status, battery)

let observation = Task {
    for await (_, currentStatus, currentBattery) in samples {
        print("\(currentStatus), battery: \(currentBattery)%")
    }
}

try await Task.sleep(nanoseconds: 2_000_000_000)
observation.cancel()
await observation.value
```

Both `withLatest` overloads finish when the source finishes. A sampled sequence that finishes after emitting a value leaves its last value available for later samples. Use `try` when an input can throw. The sampled sequences and their elements must be `Sendable`.

## Sending values with channels and subjects

Choose a channel when consumers divide the work: each element goes to one consumer. Choose a subject when all current consumers should receive each element.

### `AsyncBufferedChannel`: queue work for consumers

`send(_:)` is synchronous. Values wait in an unbounded buffer until a consumer requests them. `finish()` ends the channel after queued values have been read.

```swift
let jobs = AsyncBufferedChannel<String>()

jobs.send("Resize photo")
jobs.send("Upload photo")
jobs.finish()

for await job in jobs {
    print(job)
}
// Prints: Resize photo, Upload photo
```

You can send from one task while consuming from another. If several consumers read the same channel, they divide its elements; the channel does not broadcast them. `send` does not wait for a consumer to process a value, so a fast producer can grow the buffer.

### `AsyncThrowingBufferedChannel`: queue work that can fail

Use `AsyncThrowingBufferedChannel<Element, Error>` when the producer needs to signal failure. Call `finish()` for normal completion or `fail(_:)` for an error.

```swift
enum JobError: Error {
    case uploadFailed
}

let jobs = AsyncThrowingBufferedChannel<String, Error>()
jobs.send("Resize photo")
jobs.fail(JobError.uploadFailed)

do {
    for try await job in jobs {
        print(job)
    }
} catch {
    print("Job failed: \(error)")
}
// Prints: Resize photo, then Job failed: uploadFailed
```

### Subjects

Subjects broadcast values to registered consumers. Their element type must be `Sendable`.

| Subject | What a new consumer receives while the subject is active |
| --- | --- |
| `AsyncPassthroughSubject<Element>` | Values sent after it registers. |
| `AsyncCurrentValueSubject<Element>` | The current value, then future values. |
| `AsyncReplaySubject<Element>` | Up to `bufferSize` previous values, then future values. |
| `AsyncThrowingPassthroughSubject<Element, Failure>` | Passthrough values, with support for failure. |
| `AsyncThrowingCurrentValueSubject<Element, Failure>` | The current value and future values, with support for failure. |
| `AsyncThrowingReplaySubject<Element, Failure>` | Buffered history and future values, with support for failure. |

#### Passthrough: broadcast new events

Register each consumer before sending values it needs to receive. Registration happens in `makeAsyncIterator()`, so this example registers both consumers explicitly:

```swift
let events = AsyncPassthroughSubject<String>()
var screen = events.makeAsyncIterator()
var logger = events.makeAsyncIterator()

events.send("Signed in")
events.send(.finished)

print(await screen.next() as Any)
print(await logger.next() as Any)
// Both print: Optional("Signed in")
```

A `for await` loop registers when the loop starts. Starting a `Task` containing that loop does not guarantee it has registered before the next line of the caller runs. Values sent before a passthrough consumer registers are lost for that consumer.

#### Current value: observe state and its updates

A current-value subject starts with a value. Read or update it through `value`, or update it with `send(_:)`.

```swift
let status = AsyncCurrentValueSubject("Idle")
var updates = status.makeAsyncIterator()

status.value = "Loading"
status.send("Ready")
status.send(.finished)

while let value = await updates.next() {
    print(value)
}
// Prints: Idle, Loading, Ready

print(status.value)
// Prints: Ready
```

#### Replay: keep recent history for new consumers

The replay buffer keeps the most recent values. Register the consumer before finishing the subject; termination clears the history for future subscribers.

```swift
let messages = AsyncReplaySubject<String>(bufferSize: 2)
messages.send("First")
messages.send("Second")
messages.send("Third")

var recentMessages = messages.makeAsyncIterator()
messages.send("Fourth")
messages.send(.finished)

while let message = await recentMessages.next() {
    print(message)
}
// Prints: Second, Third, Fourth
```

`bufferSize: 0` keeps no history and still broadcasts live values. The replay limit applies to history for new consumers. Each existing consumer has its own unbounded buffer for values it has not read yet.

#### Throwing subjects: end observation with an error

Throwing subjects behave like their nonthrowing counterparts, with an extra `.failure(error)` termination. Use `Error` as the failure type to accept any error, or choose a specific error type.

```swift
enum ConnectionError: Error {
    case disconnected
}

let events = AsyncThrowingPassthroughSubject<String, ConnectionError>()
var updates = events.makeAsyncIterator()

events.send("Connected")
events.send(.failure(.disconnected))

do {
    while let event = try await updates.next() {
        print(event)
    }
} catch {
    print("Connection ended: \(error)")
}
// Prints: Connected, then Connection ended: disconnected
```

To retain state or history, choose the corresponding throwing subject:

```swift
let status = AsyncThrowingCurrentValueSubject<String, Error>("Connecting")
status.value = "Connected"
status.send(.finished)

let history = AsyncThrowingReplaySubject<String, Error>(bufferSize: 2)
history.send("Connected")
history.send(.finished)
```

The first finish or failure is permanent for every subject. Later values and termination signals are ignored. A current-value subject keeps its last accepted `value`, but consumers registering after termination receive only the finish or failure. They receive no current value or replayed history.

Concurrent sends have one shared order for consumers registered for those sends; which producer goes first is unspecified. A call to `send` does not wait for consumer code to process the element.

### `@Streamed`: observe changes to a property

`@Streamed` exposes the property's current value and subsequent assignments as an `AnyAsyncSequence` through `$property`.

```swift
final class Player {
    @Streamed var score = 0
}

let player = Player()
var scores = player.$score.makeAsyncIterator()
player.score = 10

print(try await scores.next() as Any)
print(try await scores.next() as Any)
// Prints: Optional(0), then Optional(10)
```

The projected sequence uses type erasure, so iteration requires `try`. It stays open to observe later assignments. For a long-running loop, keep its task and cancel it when observation ends. The wrapper does not add actor isolation to the containing object.

## Sharing a sequence

### `share`: give consumers one upstream iteration

`share()` lets multiple consumers receive values from one upstream iterator. Create it once and give every consumer the same returned instance. Iteration starts automatically when a consumer requests a value.

```swift
let updates = AsyncLazySequence(["Connected", "Disconnected"]).share()

// Register both consumers before either starts pulling values.
var screenUpdates = updates.makeAsyncIterator()
var logUpdates = updates.makeAsyncIterator()

while let update = try await screenUpdates.next() {
    print("Screen: \(update)")
}
while let update = try await logUpdates.next() {
    print("Log: \(update)")
}
// Prints both values for the screen, then both values for the log.
```

`share` uses a throwing passthrough subject, so consumers use `try` and receive only values produced after they register. It does not replay earlier values to a late subscriber. Put work that should run once, such as a transformation or logging callback, before `share()`.

Calling `source.share()` separately for each consumer creates separate upstream iterators. This matters especially for `AsyncThrowingStream`, whose iterator does not support overlapping calls to `next()`.

Cancelling one subscriber ends that subscriber's observation without cancelling the shared upstream. The producer's owner remains responsible for finishing its source or cancelling its producer task.

### `multicast`: choose the subject and control when iteration starts

`multicast(_:)` also shares one upstream iterator, but lets you supply the subject and call `connect()` explicitly. Its subject must have `Failure == Error`; use a throwing passthrough, current-value, or replay subject.

```swift
let history = AsyncThrowingReplaySubject<Int, Error>(bufferSize: 1)
let numbers = AsyncLazySequence([1, 2, 3]).multicast(history)
var updates = numbers.makeAsyncIterator()

numbers.connect()

while let number = try await updates.next() {
    print(number)
}
// Prints: 1, 2, 3
```

Register all consumers that need the initial values before connecting and consuming. `connect()` allows consumers to pull values; it does not consume the source by itself. The supplied subject determines what a late subscriber receives while the sequence remains active.

Call `autoconnect()` if explicit connection control is unnecessary:

```swift
let subject = AsyncThrowingPassthroughSubject<Int, Error>()
let numbers = AsyncLazySequence([1, 2, 3])
    .multicast(subject)
    .autoconnect()

print(try await numbers.collect())
// Prints: [1, 2, 3]
```

Keep and reuse one multicast instance for all consumers, just as with `share`. Reusing only the subject while creating new multicast wrappers still creates multiple upstream iterators.

## Managing observation tasks

For an open-ended stream, keep the consuming task so its owner can stop observation:

```swift
let status = AsyncCurrentValueSubject("Idle")
let observation = Task {
    for await value in status {
        print(value)
    }
}

// When the owner stops observing:
observation.cancel()
await observation.value
```

When the producer has ended for everyone, finish the subject with `subject.send(.finished)`, finish the channel with `channel.finish()`, or finish the stream's continuation. Dropping a task handle, removing a sequence from a collection, or weakly capturing an owner does not cancel an active task.

Subject subscriptions unregister when their task is cancelled or their last iterator copy is released. An early loop exit releases its subscription when that iterator is released. Keep those lifetimes in mind if you store iterators yourself.

## Using Swift Async Algorithms

You can use AsyncExtensions alongside Apple's [Swift Async Algorithms](https://github.com/apple/swift-async-algorithms). Add its package to your manifest's dependencies:

```swift
.package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0")
```

Then add its product to the same target's dependencies alongside AsyncExtensions:

```swift
.product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
```

Import both modules where you use them:

```swift
import AsyncAlgorithms
import AsyncExtensions

let numbers = [1, 2, 3].async
let letters = ["a", "b", "c"].async

for await (number, letter) in AsyncAlgorithms.zip(numbers, letters) {
    print("\(number): \(letter)")
}
// Prints: 1: a, 2: b, 3: c
```

`.async` and the two- and three-input tuple-based `zip` implementations come from AsyncAlgorithms. That package also provides two- and three-input `merge`. AsyncExtensions provides variadic `zip` and `merge`, including four or more inputs. Qualify calls with `AsyncExtensions.zip(...)` or `AsyncExtensions.merge(...)` when you want those implementations, especially with two or three inputs.

When migrating older AsyncExtensions code, add the AsyncAlgorithms dependency and import for `.async` and its fixed-arity combiners. Rename the old buffered `AsyncTimerSequence` to `AsyncBufferedTimerSequence`. Apple's `AsyncTimerSequence` uses a clock; AsyncExtensions' buffered timer emits `Date` values and takes a `DispatchTimeInterval`.

## License

AsyncExtensions is available under the [MIT license](LICENSE).
