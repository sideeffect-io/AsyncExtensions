//
//  AsyncJustSequence.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

/// `AsyncJustSequence` is an AsyncSequence that outputs a single value and finishes.
/// If the parent task is cancelled while iterating then the iteration finishes before emitting the value.
///
/// ```
/// let justSequence = AsyncJustSequence<Int>(1)
/// for await element in justSequence {
///   // will be called once with element = 1
/// }
/// ```
public struct AsyncJustSequence<Element>: AsyncSequence {
  public typealias Element = Element
  public typealias AsyncIterator = Iterator

  let element: Element?

  public init(_ element: Element?) {
    self.element = element
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(element: self.element)
  }

  public struct Iterator: AsyncIteratorProtocol {
    let element: Element?
    let isConsumed = ManagedCriticalState<Bool>(false)

    public mutating func next() async -> Element? {
      guard !Task.isCancelled else { return nil }

      let shouldEarlyReturn = self.isConsumed.withCriticalRegion { isConsumed -> Bool in
        if !isConsumed {
          isConsumed = true
          return false
        }
        return true
      }

      if shouldEarlyReturn { return nil }

      return self.element
    }
  }
}

extension AsyncJustSequence: Sendable where Element: Sendable {}
extension AsyncJustSequence.Iterator: Sendable where Element: Sendable {}
