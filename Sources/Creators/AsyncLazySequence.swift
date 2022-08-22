//
//  AsyncLazySequence.swift
//  
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

public extension Sequence {
  /// Creates an AsyncSequence of the sequence elements.
  /// - Returns: The AsyncSequence that outputs the elements from the sequence.
  var async: AsyncLazySequence<Self> {
    AsyncLazySequence(self)
  }
}

/// `AsyncLazySequence` is an AsyncSequence that outputs elements from a traditional Sequence.
/// If the parent task is cancelled while iterating then the iteration finishes.
///
/// ```
/// let fromSequence = AsyncLazySequence([1, 2, 3, 4, 5])
///
/// for await element in fromSequence {
///   print(element) // will print 1 2 3 4 5
/// }
/// ```
public struct AsyncLazySequence<Base: Sequence>: AsyncSequence {
  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  private var base: Base

  public init(_ base: Base) {
    self.base = base
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(base: self.base.makeIterator())
  }

  public struct Iterator: AsyncIteratorProtocol {
    var base: Base.Iterator

    public mutating func next() async -> Base.Element? {
      guard !Task.isCancelled else { return nil }
      return self.base.next()
    }
  }
}

extension AsyncLazySequence: Sendable where Base: Sendable {}
extension AsyncLazySequence.Iterator: Sendable where Base.Iterator: Sendable {}
