//
//  AsyncMerge2Sequence.swift
//
//
//  Created by Thibault Wittemberg on 31/03/2022.
//

/// Creates an asynchronous sequence of elements from two underlying asynchronous sequences
public func merge<Base1: AsyncSequence, Base2: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2
) -> AsyncMerge2Sequence<Base1, Base2> {
  AsyncMerge2Sequence(base1, base2)
}

/// An asynchronous sequence of elements from two underlying asynchronous sequences
///
/// In a `AsyncMerge2Sequence` instance, the *i*th element is the *i*th element
/// resolved in sequential order out of the two underlying asynchronous sequences.
/// Use the `merge(_:_:)` function to create an `AsyncMerge2Sequence`.
public struct AsyncMerge2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: AsyncSequence
where Base1.Element == Base2.Element {
  public typealias Element = Base1.Element
  public typealias AsyncIterator = Iterator

  let base1: Base1
  let base2: Base2

  public init(_ base1: Base1, _ base2: Base2) {
    self.base1 = base1
    self.base2 = base2
  }

  public func makeAsyncIterator() -> Iterator {
    Iterator(
      base1: self.base1,
      base2: self.base2
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    let mergeStateMachine: MergeStateMachine<Element>

    init(base1: Base1, base2: Base2) {
      self.mergeStateMachine = MergeStateMachine(
        base1,
        base2
      )
    }

    public mutating func next() async rethrows -> Element? {
      let mergedElement = await self.mergeStateMachine.next()
      switch mergedElement {
        case .element(let result):
          return try result._rethrowGet()
        case .termination:
          return nil
      }
    }
  }
}

extension AsyncMerge2Sequence: Sendable where Base1: Sendable, Base2: Sendable {}
