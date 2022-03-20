//
//  AsyncSequences+Timer.swift
//  
//
//  Created by Thibault Wittemberg on 04/03/2022.
//

import Foundation

public extension AsyncSequences {
    typealias Timer = AsyncTimerSequence
}

/// `AsyncTimerSequence`is an async sequence that repeatedly emits the current date on the given interval, with the given priority.
public class AsyncTimerSequence: AsyncSequence {
    public typealias Element = Date
    public typealias AsyncIterator = AsyncThrowingStream<Date, Error>.AsyncIterator

    let priority: TaskPriority?
    let interval: AsyncSequences.Interval
    var task: Task<Void, Error>?

    /// Created an async sequence that repeatedly emits the current date on the given interval, with the given priority.
    ///
    /// ```
    /// let timer = AsyncSequences.Timer(priority: .high, every: .seconds(1))
    ///
    /// Task {
    ///     for try await element in timer {
    ///         print(element)
    ///     }
    /// }
    ///
    /// // will print:
    /// // 2022-03-06 19:31:22 +0000
    /// // 2022-03-06 19:31:23 +0000
    /// // 2022-03-06 19:31:24 +0000
    /// // 2022-03-06 19:31:25 +0000
    /// // 2022-03-06 19:31:26 +0000
    /// // and will stop once timer.cancel() is called or the parent task is cancelled.
    /// ```
    ///
    /// - Parameters:
    ///   - priority: The priority of the inderlying Task. Nil by default.
    ///   - interval: The time interval on which to publish events. For example, a value of `0.5` publishes an event approximately every half-second.
    /// - Returns: An async sequence that repeatedly emits the current date on the given interval, with the given priority.
    public init(priority: TaskPriority? = nil, every interval: AsyncSequences.Interval) {
        self.priority = priority
        self.interval = interval
    }

    func makeStream() -> AsyncThrowingStream<Date, Error> {
        AsyncThrowingStream<Date, Error>(Date.self, bufferingPolicy: .unbounded) { [weak self] continuation in
            let interval = self?.interval ?? .immediate
            self?.task = Task(priority: self?.priority) {
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: interval.value)
                        continuation.yield(Date())
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    throw error
                }
            }
        }
    }

    /// Cancels the timer.
    public func cancel() {
        self.task?.cancel()
    }

    public func makeAsyncIterator() -> AsyncIterator {
        self.makeStream().makeAsyncIterator()
    }
}
