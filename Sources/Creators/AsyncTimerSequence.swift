//
//  AsyncSequences+Timer.swift
//  
//
//  Created by Thibault Wittemberg on 04/03/2022.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
import Dispatch
#else
@preconcurrency import Foundation
#endif

private extension DispatchTimeInterval {
  var nanoseconds: UInt64 {
    switch self {
      case .nanoseconds(let value) where value >= 0: return UInt64(value)
      case .microseconds(let value) where value >= 0: return UInt64(value) * 1000
      case .milliseconds(let value) where value >= 0: return UInt64(value) * 1_000_000
      case .seconds(let value) where value >= 0: return UInt64(value) * 1_000_000_000
      case .never: return .zero
      default: return .zero
    }
  }
}

/// `AsyncTimerSequence`is an async sequence that repeatedly emits the current date on the given interval, with the given priority.
/// The Dates will be buffered until the consumers are available to process them.
///
/// ```
/// let timer = AsyncTimerSequence(priority: .high, every: .seconds(1))
///
/// Task {
///   for try await element in timer {
///     print(element)
///   }
/// }
///
/// // will print:
/// // 2022-03-06 19:31:22 +0000
/// // 2022-03-06 19:31:23 +0000
/// // 2022-03-06 19:31:24 +0000
/// // 2022-03-06 19:31:25 +0000
/// // 2022-03-06 19:31:26 +0000
/// ```
public struct AsyncTimerSequence: AsyncSequence {
  public typealias Element = Date
  public typealias AsyncIterator = Iterator

  let priority: TaskPriority?
  let interval: DispatchTimeInterval

  /// - Parameters:
  ///   - priority: The priority of the inderlying Task. Nil by default.
  ///   - interval: The time interval on which to publish events.
  ///   For example, a value of `.milliseconds(500)`publishes an event approximately every half-second.
  /// - Returns: An async sequence that repeatedly emits the current date on the given interval, with the given priority.
  public init(priority: TaskPriority? = nil, every interval: DispatchTimeInterval) {
    self.priority = priority
    self.interval = interval
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(priority: self.priority, interval: self.interval)
  }

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    let asyncChannel: AsyncBufferedChannel<Date>
    var iterator: AsyncBufferedChannel<Date>.Iterator
    let task: Task<Void, Never>

    init(priority: TaskPriority?, interval: DispatchTimeInterval) {
      self.asyncChannel = AsyncBufferedChannel()
      self.iterator = self.asyncChannel.makeAsyncIterator()
      self.task = Task(priority: priority) { [asyncChannel] in
        while !Task.isCancelled {
          asyncChannel.send(Date())
          try? await Task.sleep(nanoseconds: interval.nanoseconds)
        }
        asyncChannel.finish()
      }
    }

    public mutating func next() async -> Element? {
      await withTaskCancellationHandler {
        guard !Task.isCancelled else { return nil }
        return await self.iterator.next()
      } onCancel: { [task] in
        task.cancel()
      }
    }
  }
}
