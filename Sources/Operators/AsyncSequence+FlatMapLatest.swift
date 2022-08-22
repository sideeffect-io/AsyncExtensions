//
//  AsyncSequence+FlatMapLatest.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

public extension AsyncSequence {
  /// Transforms  the async sequence elements into a async sequence and flattens the sequence of events
  /// from these multiple sources async sequences to appear as if they were coming from a single async sequence of events.
  /// Mapping to a new async sequence will cancel the task related to the previous one.
  ///
  /// ```
  /// let sourceSequence = AsyncSequences.From([1, 2, 3])
  /// let flatMapLatestSequence = sourceSequence.map { element in ["a\(element)", "b\(element)"] }
  ///
  /// for try await element in flatMapLatestSequence {
  ///     print(element)
  /// }
  ///
  /// // will print:
  /// a3, b3
  /// ```
  ///
  /// - parameter transform: A transform to apply to each  value of the async sequence, from which you can return a new async sequence.
  /// - note: This operator is a combination of `map` and `switchToLatest`.
  /// - returns: An async sequence emitting the values of the latest inner async sequence.
  func flatMapLatest<OutputAsyncSequence: AsyncSequence>(
    _ transform: @Sendable @escaping (Element) async -> OutputAsyncSequence
  ) -> AsyncSwitchToLatestSequence<AsyncMapSequence<Self, OutputAsyncSequence>> {
    self.map(transform).switchToLatest()
  }

  /// Transforms  the async sequence elements into a async sequence and flattens the sequence of events
  /// from these multiple sources async sequences to appear as if they were coming from a single async sequence of events.
  /// Mapping to a new async sequence will cancel the task related to the previous one.
  ///
  /// ```
  /// let sourceSequence = [1, 2, 3].async
  /// let flatMapLatestSequence = sourceSequence.map { element in ["a\(element)", "b\(element)"] }
  ///
  /// for try await element in flatMapLatestSequence {
  ///     print(element)
  /// }
  ///
  /// // will print:
  /// a3, b3
  /// ```
  ///
  /// - parameter transform: A throwing transformation to apply to each  value of the async sequence,
  /// from which you can return a new async sequence.
  /// - note: This operator is a combination of `map` and `switchToLatest`.
  /// - returns: An async sequence emitting the values of the latest inner async sequence.
  func flatMapLatest<OutputAsyncSequence: AsyncSequence>(
    _ transform: @Sendable @escaping (Element) async throws -> OutputAsyncSequence
  ) -> AsyncSwitchToLatestSequence<AsyncThrowingMapSequence<Self, OutputAsyncSequence>> {
    self.map(transform).switchToLatest()
  }

  /// Transforms  the async sequence elements into a async element pretty much as a map function would do,
  /// except that mapping to a new element will cancel the task related to the previous one.
  ///
  /// ```
  /// let sourceSequence = [1, 2, 3].async
  /// let flatMapLatestSequence = sourceSequence.map { element in await newOutput(element) } // where newOutput is a async function
  ///
  /// for try await element in flatMapLatestSequence {
  ///     print(element)
  /// }
  ///
  /// // will print:
  /// a3, b3
  /// ```
  ///
  /// - note: This operator is a combination of `map` and `switchToLatest`.
  /// - Returns: An async sequence emitting the value of the latest inner async sequence.
  func flatMapLatest<Output>(
    _ transform: @Sendable @escaping (Element) async throws -> Output
  ) -> AsyncSwitchToLatestSequence<AsyncThrowingMapSequence<Self, AsyncThrowingJustSequence<Output>>> where Element: Sendable {
    self.map { element in AsyncThrowingJustSequence { try await transform(element) } }.switchToLatest()
  }
}
