//
//  AsyncEmptySequence.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

/// `AsyncEmptySequence` is an AsyncSequence that immediately finishes without emitting values.
///
/// ```
/// let emptySequence = AsyncEmptySequence<Int>()
/// for try await element in emptySequence {
///   // will never be called
/// }
/// ```
public struct AsyncEmptySequence<Element>: AsyncSequence, Sendable {
  public typealias Element = Element
  public typealias AsyncIterator = Iterator

  public init() {}

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator()
  }

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    public func next() async -> Element? {
      nil
    }
  }
}
