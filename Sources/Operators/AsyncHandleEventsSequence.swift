//
//  AsyncSequence+HandleEvents.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

public extension AsyncSequence {
  /// Performs the specified closures when async sequences events occur.
  ///
  /// ```
  /// let sourceSequence = AsyncLazySequence([1, 2, 3, 4, 5])
  /// let handledSequence = sourceSequence.handleEvents {
  ///    print("Begin looping")
  /// } onElement: { element in
  ///    print("Element is \(element)")
  /// } onCancel: {
  ///    print("Cancelled")
  /// } onFinish: { termination in
  ///    print(termination)
  /// }
  ///
  /// for try await element in handledSequence {}
  ///
  /// // will print:
  /// // Begin looping
  /// // Element is 1
  /// // Element is 2
  /// // Element is 3
  /// // Element is 4
  /// // Element is 5
  /// // finished
  /// ```
  ///
  /// - Parameters:
  ///   - onStart: The operation to execute when the async sequence is first iterated.
  ///   - onElement: The operation to execute on each element.
  ///   - onCancel: The operation to execute when the task suppoerting the async sequence looping is cancelled.
  ///   - onFinish: The operation to execute when the async sequence looping is finished,
  ///   whether it is due to an error or a normal termination.
  /// - Returns: The AsyncSequence that executes the `receiveElement` operation for each element of the source sequence.
  func handleEvents(
    onStart: (@Sendable () async throws -> Void)? = nil,
    onElement: (@Sendable (Element) async -> Void)? = nil,
    onCancel: (@Sendable () async -> Void)? = nil,
    onFinish: (@Sendable (Termination<Error>) async -> Void)? = nil
  ) -> AsyncHandleEventsSequence<Self> {
    AsyncHandleEventsSequence(
      self,
      onStart: onStart,
      onElement: onElement,
      onCancel: onCancel,
      onFinish: onFinish
    )
  }
}

public struct AsyncHandleEventsSequence<Base: AsyncSequence>: AsyncSequence {
  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  var base: Base
  let onStart: (@Sendable () async throws -> Void)?
  let onElement: (@Sendable (Base.Element) async -> Void)?
  let onCancel: (@Sendable () async -> Void)?
  let onFinish: (@Sendable (Termination<Error>) async -> Void)?

  public init(
    _ base: Base,
    onStart: (@Sendable () async throws -> Void)?,
    onElement: (@Sendable (Base.Element) async -> Void)?,
    onCancel: (@Sendable () async -> Void)?,
    onFinish: (@Sendable (Termination<Error>) async -> Void)?
  ) {
    self.base = base
    self.onStart = onStart
    self.onElement = onElement
    self.onCancel = onCancel
    self.onFinish = onFinish
  }

  public func makeAsyncIterator() -> AsyncIterator {
    Iterator(
      base: self.base.makeAsyncIterator(),
      onStart: self.onStart,
      onElement: self.onElement,
      onCancel: self.onCancel,
      onFinish: self.onFinish
    )
  }

  public struct Iterator: AsyncIteratorProtocol {
    var base: Base.AsyncIterator

    let onStart: (@Sendable () async throws -> Void)?
    let onElement: (@Sendable (Base.Element) async -> Void)?
    let onCancel: (@Sendable () async -> Void)?
    let onFinish: (@Sendable (Termination<Error>) async -> Void)?

    let onStartExecuted = ManagedCriticalState<Bool>(false)

    public init(
      base: Base.AsyncIterator,
      onStart: (@Sendable () async throws -> Void)?,
      onElement: (@Sendable (Base.Element) async -> Void)?,
      onCancel: (@Sendable () async -> Void)?,
      onFinish: (@Sendable (Termination<Error>) async -> Void)?
    ) {
      self.base = base
      self.onStart = onStart
      self.onElement = onElement
      self.onCancel = onCancel
      self.onFinish = onFinish
    }

    public mutating func next() async throws -> Element? {
      guard !Task.isCancelled else {
        await self.onCancel?()
        return nil
      }

      do {
        let shouldCallOnStart = self.onStartExecuted.withCriticalRegion { onStartExecuted -> Bool in
          if !onStartExecuted {
            onStartExecuted = true
            return true
          }
          return false
        }

        if shouldCallOnStart {
          try await self.onStart?()
        }

        let nextElement = try await self.base.next()

        if let element = nextElement {
          await self.onElement?(element)
        } else {
          if Task.isCancelled {
            await self.onCancel?()
          } else {
            await self.onFinish?(.finished)
          }
        }

        return nextElement
      } catch let error as CancellationError {
        await self.onCancel?()
        throw error
      } catch {
        await self.onFinish?(.failure(error))
        throw error
      }
    }
  }
}

extension AsyncHandleEventsSequence: Sendable where Base: Sendable {}
extension AsyncHandleEventsSequence.Iterator: Sendable where Base.AsyncIterator: Sendable {}
