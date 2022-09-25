//
//  AsyncPrependSequence.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

public extension AsyncSequence {
  /// Prepends an element to the upstream async sequence.
  ///
  /// ```
  /// let sourceSequence = AsyncLazySequence([1, 2, 3])
  /// let prependSequence = sourceSequence.prepend(0)
  ///
  /// for try await element in prependSequence {
  ///     print(element)
  /// }
  ///
  /// // will print:
  /// // Element is 0
  /// // Element is 1
  /// // Element is 2
  /// // Element is 3
  /// ```
  ///
  /// - Parameter element: The element to prepend.
  /// - Returns: The async sequence prepended with the element.
  func prepend(_ element: @Sendable @autoclosure @escaping () -> Element) -> AsyncPrependSequence<Self> {
    AsyncPrependSequence(self, prependElement: element())
  }
}

public struct AsyncPrependSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  private var base: Base
  private var prependElement: @Sendable () -> Element

  public init(
    _ base: Base,
    prependElement: @Sendable @autoclosure @escaping () -> Element
  ) {
    self.base = base
    self.prependElement = prependElement
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      base: self.base.makeAsyncIterator(),
      prependElement: self.prependElement
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator
    var prependElement: () async throws -> Element
    var hasBeenDelivered = false

    public init(
      base: Base.AsyncIterator,
      prependElement: @escaping () async throws -> Element
    ) {
      self.base = base
      self.prependElement = prependElement
    }

    public mutating func next() async throws -> Element? {
      guard !Task.isCancelled else { return nil }

      if !self.hasBeenDelivered {
        self.hasBeenDelivered = true
        return try await prependElement()
      }

      return try await self.base.next()
    }
  }
}

extension AsyncPrependSequence: Sendable where Base: Sendable {}
