//
//  AsyncZipSequence.swift
//  
//
//  Created by Thibault Wittemberg on 24/09/2022.
//

/// `zip` produces an `AsyncSequence` that combines the latest elements from  sequences according to their temporality
/// and emits an array to the client. If any Async Sequence ends successfully or fails with an error, so to does the zipped
/// Async Sequence.
///
/// ```
/// let asyncSequence1 = [1, 2, 3, 4, 5].async
/// let asyncSequence2 = [1, 2, 3, 4, 5].async
/// let asyncSequence3 = [1, 2, 3, 4, 5].async
/// let asyncSequence4 = [1, 2, 3, 4, 5].async
/// let asyncSequence5 = [1, 2, 3, 4, 5].async
///
/// let zippedAsyncSequence = zip(asyncSequence1, asyncSequence2, asyncSequence3, asyncSequence4, asyncSequence5)
///
/// for await element in zippedAsyncSequence {
///   print(element) // will print -> [1, 1, 1, 1, 1] [2, 2, 2, 2, 2] [3, 3, 3, 3, 3] [4, 4, 4, 4, 4] [5, 5, 5, 5, 5]
/// }
/// ```
/// Use the `zip(_:)` function to create an `AsyncZipSequence`.
public func zip<Base: AsyncSequence>(_ bases: Base...) -> AsyncZipSequence<Base> {
  AsyncZipSequence(bases)
}

public struct AsyncZipSequence<Base: AsyncSequence>: AsyncSequence
where Base: Sendable, Base.Element: Sendable {
  public typealias Element = [Base.Element]
  public typealias AsyncIterator = Iterator

  let bases: [Base]

  init(_ bases: [Base]) {
    self.bases = bases
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(bases)
  }

  public struct Iterator: AsyncIteratorProtocol {
    let runtime: ZipRuntime<Base>

    init(_ bases: [Base]) {
      self.runtime = ZipRuntime(bases)
    }

    public func next() async rethrows -> Element? {
      try await self.runtime.next()
    }
  }
}
