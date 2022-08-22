//
//  AsyncFailSequence.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

/// `AsyncFailSequence` is an AsyncSequence that outputs no elements and throws an error.
/// If the parent task is cancelled while iterating then the iteration finishes before emitting the error.
///
/// ```
/// let failSequence = AsyncFailSequence<Int, Swift.Error>(NSError(domain: "", code: 1))
/// do {
///   for try await element in failSequence {
///     // will never be called
///   }
/// } catch {
///   // will catch `NSError(domain: "", code: 1)` here
/// }
/// ```
public struct AsyncFailSequence<Element>: AsyncSequence, Sendable {
  public typealias Element = Element
  public typealias AsyncIterator = Iterator

  let error: Error

  public init<Failure: Error>(_ error: Failure) {
    self.error = error
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(error: self.error)
  }

  public struct Iterator: AsyncIteratorProtocol, Sendable {
    var error: Error?

    public mutating func next() async throws -> Element? {
      guard !Task.isCancelled else { return nil }

      guard let error = self.error else {
        return nil
      }

      self.error = nil
      throw error
    }
  }
}
