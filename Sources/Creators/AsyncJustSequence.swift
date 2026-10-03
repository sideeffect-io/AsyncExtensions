//
//  AsyncJustSequence.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

/// `AsyncJustSequence` is an AsyncSequence that outputs a single value and finishes.
/// If the parent task is cancelled while iterating then the iteration finishes before emitting the value.
///
/// ```
/// let justSequence = AsyncJustSequence<Int>(1)
/// for await element in justSequence {
///   // will be called once with element = 1
/// }
/// ```
public struct AsyncJustSequence<Element>: AsyncSequence {
  public typealias Element = Element
  public typealias AsyncIterator = Iterator

  enum Source {
    case value(Element?)
    case factory(@Sendable () async -> Element?)
  }

  let source: Source

  public init(_ element: Element?) {
    self.source = .value(element)
  }

  /// Creates a single value lazily for each iterator. Returning nil finishes without a value.
  public init(factory: @Sendable @escaping () async -> Element?) {
    self.source = .factory(factory)
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(source: self.source)
  }

  public struct Iterator: AsyncIteratorProtocol {
    let pendingSource: ManagedCriticalState<Source?>

    init(source: Source) {
      self.pendingSource = ManagedCriticalState(source)
    }

    public mutating func next() async -> Element? {
      let source = self.pendingSource.withCriticalRegion { pendingSource -> Source? in
        defer { pendingSource = nil }
        return pendingSource
      }
      guard !Task.isCancelled, let source = source else { return nil }
      switch source {
        case .value(let element):
          return element
        case .factory(let factory):
          let element = await factory()
          return Task.isCancelled ? nil : element
      }
    }
  }
}

extension AsyncJustSequence: Sendable where Element: Sendable {}
extension AsyncJustSequence.Source: Sendable where Element: Sendable {}
extension AsyncJustSequence.Iterator: Sendable where Element: Sendable {}
