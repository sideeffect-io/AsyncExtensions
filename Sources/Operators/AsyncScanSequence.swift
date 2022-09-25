//
//  AsyncSequence+Scan.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

public extension AsyncSequence {
  /// Transforms elements from the upstream async sequence by providing the current element to a closure
  /// along with the last value returned by the closure.
  ///
  /// ```
  /// let sourceSequence = AsyncLazySequence([1, 2, 3, 4, 5])
  /// let scannedSequence = sourceSequence.scan("") { accumulator, element in
  ///     return accumulator + "\(element)"
  /// }
  /// for try await element in scannedSequence {
  ///     print(element)
  /// }
  ///
  /// // will print:
  /// "1"
  /// "12"
  /// "123"
  /// "1234"
  /// "12345"
  /// ```
  ///
  /// - Parameters:
  ///   - initialResult: The initial value of the result.
  ///   - nextPartialResult: The closure to execute on each element of the source sequence.
  /// - Returns: The async sequence of all the partial results.
  func scan<Output>(
    _ initialResult: Output,
    _ nextPartialResult: @Sendable @escaping (Output, Element) async -> Output
  ) -> AsyncScanSequence<Self, Output> {
    AsyncScanSequence(self, initialResult: initialResult, nextPartialResult: nextPartialResult)
  }
}

public struct AsyncScanSequence<Base: AsyncSequence, Output>: AsyncSequence {
  public typealias Element = Output
  public typealias AsyncIterator = Iterator

  var base: Base
  var initialResult: Output
  let nextPartialResult: @Sendable (Output, Base.Element) async -> Output

  public init(
    _ base: Base,
    initialResult: Output,
    nextPartialResult: @Sendable @escaping (Output, Base.Element) async -> Output
  ) {
    self.base = base
    self.initialResult = initialResult
    self.nextPartialResult = nextPartialResult
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      base: self.base.makeAsyncIterator(),
      initialResult: self.initialResult,
      nextPartialResult: self.nextPartialResult
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator
    var currentValue: Output
    let nextPartialResult: @Sendable (Output, Base.Element) async -> Output

    public init(
      base: Base.AsyncIterator,
      initialResult: Output,
      nextPartialResult: @Sendable @escaping (Output, Base.Element) async -> Output
    ) {
      self.base = base
      self.currentValue = initialResult
      self.nextPartialResult = nextPartialResult
    }

    public mutating func next() async rethrows -> Output? {
      let nextUpstreamValue = try await self.base.next()
      guard let nonNilNextUpstreamValue = nextUpstreamValue else { return nil }
      self.currentValue = await self.nextPartialResult(self.currentValue, nonNilNextUpstreamValue)
      return self.currentValue
    }
  }
}

extension AsyncScanSequence: Sendable where Base: Sendable, Output: Sendable {}
extension AsyncScanSequence.Iterator: Sendable where Base.AsyncIterator: Sendable, Output: Sendable {}
