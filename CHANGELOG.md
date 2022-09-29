**v0.5.1 - Nitrogen:**

This version removes compilation unsafe flags

**v0.5.0 - Carbon:**

This version brings a lot of internal refactoring and breaking changes + some new operators.

Now `swift-async-algorithms` has been anounced, this library can be seen as a companion for the Apple repo.
For now there is an overlap between both libraries, but when `swift-async-algorithms` becomes stable the overlapping operators while be deprecated in `AsyncExtensions`.

Nevertheless `AsyncExtensions` will continue to provide the operators that the community needs and are not provided by Apple.

- `AsyncBufferedChannel`/`AsyncThrowingBufferedChannel`: is the equivalent to `AsyncChannel` from Apple. The difference is that back-pressure is handled with a stack and the send operation is not suspending.
- Subjects: the `subject` suffix has been adopted to all the "hot" `AsyncSequence` with a shared output. A throwing counterpart has been added.
- `zip` and `merge` are top level functions to match Apple repo.
- `AsyncThrowingJustSequence`: an `AsyncSequence` that takes a throwing closure to compute the only element to emit.
- `AsyncStream.pipe()`: creates and `AsyncStream` by escaping the `Continuation` and returning a tuple to manipulate the inputs and outputs of the stream.
- `mapToResult()`: maps events (elements or failure) from an `AsyncSequence` to a `Result`. The resulting `AsyncSequence` cannot fail.
- `AsyncLazySequence`: is a renaming to match Apple repo for creating an `AsyncSequence` from a `Sequence`.

**v0.4.0 - Bore:**

- AsyncStreams: new @Streamed property wrapper
- AsyncSequences: finish Timer when canceled

**v0.3.0 - Beryllium:**

- Operators: new Share operator
- AsyncSequences: new Timer AsyncSequence
- AsyncStreams: `send()` functions are now synchronous

**v0.2.1 - Lithium:**

- Enforce the call of onNext in a determinitisc way

**v0.2.0 - Helium:**

- AsyncStreams.CurrentValue `element` made public and available with get/set
- new Multicast operator
- new Assign operator

**v0.1.0 - Hydrogen:**

- Implements the first set of extensions
