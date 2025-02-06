//
//  AsyncSequence+EraseToAnyAsyncSequence.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

public extension AsyncSequence {
  /// Type erase the AsyncSequence into an AnyAsyncSequence.
  /// - Returns: A type erased AsyncSequence.
  func eraseToAnyAsyncSequence() -> AnyAsyncSequence<Element> where Self: Sendable {
    AnyAsyncSequence(self)
  }
}

/// Type erased version of an AsyncSequence.
public struct AnyAsyncSequence<Element>: AsyncSequence {
  public typealias AsyncIterator = AnyAsyncIterator<Element>

  private let makeAsyncIteratorClosure: @Sendable () -> AsyncIterator

  public init<Base: AsyncSequence>(_ base: Base) where Base.Element == Element, Base: Sendable {
    self.makeAsyncIteratorClosure = { AnyAsyncIterator(base: base.makeAsyncIterator()) }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    self.makeAsyncIteratorClosure()
  }
}

public struct AnyAsyncIterator<Element>: AsyncIteratorProtocol {
  public typealias Element = Element

  private let nextClosure: () async throws -> Element?

  public init<Base: AsyncIteratorProtocol>(base: Base) where Base.Element == Element {
    var mutableBase = base
    self.nextClosure = { try await mutableBase.next() }
  }

  public mutating func next() async throws -> Element? {
    try await self.nextClosure()
  }
}

extension AnyAsyncSequence: Sendable {}
