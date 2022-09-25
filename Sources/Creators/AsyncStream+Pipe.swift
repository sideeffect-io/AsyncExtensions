//
//  AsyncStream+Pipe.swift
//  
//
//  Created by Thibault Wittemberg on 24/09/2022.
//

public extension AsyncStream {
  /// Factory function that creates an AsyncStream and returns a tuple standing for its inputs and outputs.
  /// It easy the usage of an AsyncStream in a imperative code context.
  /// - Parameter bufferingPolicy: A `Continuation.BufferingPolicy` value to
  ///       set the stream's buffering behavior. By default, the stream buffers an
  ///       unlimited number of elements. You can also set the policy to buffer a
  ///       specified number of oldest or newest elements.
  /// - Returns: the tuple (input, output). The input can be yielded with values, the output can be iterated over
  static func pipe(
    bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
  ) -> (AsyncStream<Element>.Continuation, AsyncStream<Element>) {
    var continuation: AsyncStream<Element>.Continuation!
    let stream = AsyncStream(bufferingPolicy: bufferingPolicy) { continuation = $0 }
    return (continuation, stream)
  }
}

public extension AsyncThrowingStream {
  /// Factory function that creates an AsyncthrowingStream and returns a tuple standing for its inputs and outputs.
  /// It easy the usage of an AsyncthrowingStream in a imperative code context.
  /// - Parameter bufferingPolicy: A `Continuation.BufferingPolicy` value to
  ///       set the stream's buffering behavior. By default, the stream buffers an
  ///       unlimited number of elements. You can also set the policy to buffer a
  ///       specified number of oldest or newest elements.
  /// - Returns: the tuple (input, output). The input can be yielded with values/errors, the output can be iterated over
  static func pipe(
    bufferingPolicy: AsyncThrowingStream<Element, Error>.Continuation.BufferingPolicy = .unbounded
  ) -> (AsyncThrowingStream<Element, Error>.Continuation, AsyncThrowingStream<Element, Error>) {
    var continuation: AsyncThrowingStream<Element, Error>.Continuation!
    let stream = AsyncThrowingStream<Element, Error>(bufferingPolicy: bufferingPolicy) { continuation = $0 }
    return (continuation, stream)
  }
}
