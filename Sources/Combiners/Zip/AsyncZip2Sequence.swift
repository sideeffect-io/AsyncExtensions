//
//  AsyncZip2Sequence.swift
//
//
//  Created by Thibault Wittemberg on 13/01/2022.
//

/// `zip` produces an `AsyncSequence` that combines the latest elements from two sequences according to their temporality
/// and emits a tuple to the client. If any Async Sequence ends successfully or fails with an error, so to does the zipped
/// Async Sequence.
///
/// ```
/// let asyncSequence1 = [1, 2, 3, 4, 5].async
/// let asyncSequence2 = ["1", "2", "3", "4", "5"].async
///
/// let zippedAsyncSequence = zip(asyncSequence1, asyncSequence2)
///
/// for await element in zippedAsyncSequence {
///   print(element) // will print -> (1, "1") (2, "2") (3, "3") (4, "4") (5, "5")
/// }
/// ```
/// Use the `zip(_:_:)` function to create an `AsyncZip2Sequence`.
public func zip<Base1: AsyncSequence, Base2: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2
) -> AsyncZip2Sequence<Base1, Base2> {
  AsyncZip2Sequence(base1, base2)
}

public struct AsyncZip2Sequence<Base1: AsyncSequence, Base2: AsyncSequence>: AsyncSequence
where Base1: Sendable, Base1.Element: Sendable, Base2: Sendable, Base2.Element: Sendable {
  public typealias Element = (Base1.Element, Base2.Element)
  public typealias AsyncIterator = Iterator

  let base1: Base1
  let base2: Base2

  init(_ base1: Base1, _ base2: Base2) {
    self.base1 = base1
    self.base2 = base2
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      base1,
      base2
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    let runtime: Zip2Runtime<Base1, Base2>

    init(_ base1: Base1, _ base2: Base2) {
      self.runtime = Zip2Runtime(base1, base2)
    }

    public func next() async rethrows -> Element? {
      try await self.runtime.next()
    }
  }
}
