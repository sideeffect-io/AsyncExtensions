//
//  AsyncZip3Sequence.swift
//  
//
//  Created by Thibault Wittemberg on 24/09/2022.
//

/// `zip` produces an `AsyncSequence` that combines the latest elements from three sequences according to their temporality
/// and emits a tuple to the client. If any Async Sequence ends successfully or fails with an error, so to does the zipped
/// Async Sequence.
///
/// ```
/// let asyncSequence1 = [1, 2, 3, 4, 5].async
/// let asyncSequence2 = ["1", "2", "3", "4", "5"].async
/// let asyncSequence3 = ["A", "B", "C", "D", "E"].async
///
/// let zippedAsyncSequence = zip(asyncSequence1, asyncSequence2, asyncSequence3)
///
/// for await element in zippedAsyncSequence {
///   print(element) // will print -> (1, "1", "A") (2, "2", "B") (3, "3", "V") (4, "4", "D") (5, "5", "E")
/// }
/// ```
/// Use the `zip(_:_:_:)` function to create an `AsyncZip3Sequence`.
public func zip<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>(
  _ base1: Base1,
  _ base2: Base2,
  _ base3: Base3
) -> AsyncZip3Sequence<Base1, Base2, Base3> {
  AsyncZip3Sequence(base1, base2, base3)
}

public struct AsyncZip3Sequence<Base1: AsyncSequence, Base2: AsyncSequence, Base3: AsyncSequence>: AsyncSequence
where Base1: Sendable, Base1.Element: Sendable, Base2: Sendable, Base2.Element: Sendable, Base3: Sendable, Base3.Element: Sendable {
  public typealias Element = (Base1.Element, Base2.Element, Base3.Element)
  public typealias AsyncIterator = Iterator

  let base1: Base1
  let base2: Base2
  let base3: Base3

  init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
    self.base1 = base1
    self.base2 = base2
    self.base3 = base3
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      base1,
      base2,
      base3
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    let runtime: Zip3Runtime<Base1, Base2, Base3>

    init(_ base1: Base1, _ base2: Base2, _ base3: Base3) {
      self.runtime = Zip3Runtime(base1, base2, base3)
    }

    public func next() async rethrows -> Element? {
      try await self.runtime.next()
    }
  }
}
