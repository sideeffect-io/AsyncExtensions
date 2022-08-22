//
//  AsyncThrowingJustSequence.swift
//
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

/// `AsyncThrowingJustSequence` is an AsyncSequence that outputs a single value  from a throwing closure and finishes.
/// If the parent task is cancelled while iterating then the iteration finishes before emitting the value.
///
/// ```
/// let justSequence = AsyncThrowingJustSequence<Int> { 1 }
/// for try await element in justSequence {
///   // will be called once with element = 1
/// }
/// ```
public struct AsyncThrowingJustSequence<Element>: AsyncSequence, Sendable {
  public typealias Element = Element
  public typealias AsyncIterator = Iterator

  let factory: @Sendable () async throws -> Element?

  public init(_ element: Element?) where Element: Sendable {
    self.factory = { element }
  }

  public init(factory: @Sendable @escaping () async throws -> Element?) {
    self.factory = factory
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(factory: self.factory)
  }

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    let factory: @Sendable () async throws -> Element?
    let isConsumed = ManagedCriticalState<Bool>(false)

    public mutating func next() async throws -> Element? {
      guard !Task.isCancelled else { return nil }

      let shouldEarlyReturn = self.isConsumed.withCriticalRegion { isConsumed -> Bool in
        if !isConsumed {
          isConsumed = true
          return false
        }
        return true
      }

      if shouldEarlyReturn { return nil }

      let element = try await self.factory()
      return element
    }
  }
}
