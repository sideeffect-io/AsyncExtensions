//
//  AsyncMapToResultSequence.swift
//  
//
//  Created by Thibault Wittemberg on 28/08/2022.
//

public extension AsyncSequence {

  /// Maps elements or failures from a base sequence to a Result. The resulting async sequence cannot throw.
  /// - Returns: an async sequence with elements and failure mapped to a Result
  ///
  /// ```
  /// let subject = asyncThrowingPassthroughSubject<Int, Error>()
  /// let sequence = subject.mapToResult()
  /// Task {
  ///   for await element in sequence {
  ///     print(element) // will print .success(1), .failure(MyError)
  ///   }
  /// }
  ///
  /// subject.send(1)
  /// subject.send(.failure(MyError()))
  /// ```
  func mapToResult() -> AsyncMapToResultSequence<Self> {
    AsyncMapToResultSequence(base: self)
  }
}

public struct AsyncMapToResultSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Result<Base.Element, Error>
  public typealias AsyncIterator = Iterator

  let base: Base

  public func makeAsyncIterator() -> Iterator {
    Iterator(
      base: self.base.makeAsyncIterator()
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator

    public mutating func next() async -> Element? {
      do {
        guard let element = try await base.next() else { return nil }
        return .success(element)
      } catch {
        return .failure(error)
      }
    }
  }
}

extension AsyncMapToResultSequence: Sendable where Base: Sendable {}
extension AsyncMapToResultSequence.Iterator: Sendable where Base.AsyncIterator: Sendable {}
