//
//  AsyncSequence+MapError.swift
//
//  Created by JCSooHwanCho on 2022/03/24.
//

public extension AsyncSequence {
    /// transform error from upstream async sequence
    ///
    /// ```
    /// struct CustomError: Error { }
    ///
    /// let failSequence = AsyncSequences.Fail<Int, Swift.Error>(error: NSError(domain: "", code: 1))
    ///
    /// do {
    ///   for try await element in failSequence.mapError({ _ in CustomError() }) {
    ///       print(element)
    ///   }
    /// } catch {
    ///    print(error) // CustomError()
    /// }
    ///
    /// ```
    ///
    /// - Parameter transformError: A transform to apply to error that upstream emits.
    /// - Returns: The async sequence error transformed
  @inlinable
  __consuming func mapError(
    _ transformError: @Sendable @escaping (Error) async -> Error
  ) -> AsyncMapErrorSequence<Self> {
    return AsyncMapErrorSequence(self, transformError: transformError)
  }
}

public struct AsyncMapErrorSequence<Base: AsyncSequence> {
  @usableFromInline
  let base: Base

  @usableFromInline
  let transformError: (Error) async -> Error

  @usableFromInline
  init(
    _ base: Base,
    transformError: @escaping (Error) async -> Error
  ) {
    self.base = base
    self.transformError = transformError
  }
}

extension AsyncMapErrorSequence: AsyncSequence {

  public typealias Element = Base.Element

  public typealias AsyncIterator = Iterator

  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    var baseIterator: Base.AsyncIterator

    @usableFromInline
    let transformError: (Error) async -> Error

    @usableFromInline
    init(
      _ baseIterator: Base.AsyncIterator,
      transformError: @escaping (Error) async -> Error
    ) {
      self.baseIterator = baseIterator
      self.transformError = transformError
    }

    @inlinable
    public mutating func next() async rethrows -> Element? {
        do {
            return try await baseIterator.next()
        } catch {
            throw await transformError(error)
        }
    }
  }

  @inlinable
  public __consuming func makeAsyncIterator() -> Iterator {
      return Iterator(base.makeAsyncIterator(), transformError: transformError)
  }
}

extension AsyncMapErrorSequence: @unchecked Sendable
  where Base: Sendable,
        Base.Element: Sendable { }

extension AsyncMapErrorSequence.Iterator: @unchecked Sendable
  where Base.AsyncIterator: Sendable,
        Base.Element: Sendable { }

