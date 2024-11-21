//
//  AsyncStream+PipeTests.swift
//  
//
//  Created by Thibault Wittemberg on 25/09/2022.
//

import AsyncExtensions
import XCTest

final class AsyncStream_PipeTests: XCTestCase {
  func test_pipe_produces_stream_input_and_output() async {
    let finished = expectation(description: "The stream has finished")

    // Given
    let (input, output) = AsyncStream<Int>.pipe()

    Task {
      // Then
      var receivedElements = [Int]()
      for await element in output {
        receivedElements.append(element)
      }
      XCTAssertEqual(receivedElements, [1, 2])
      finished.fulfill()
    }

    // When
    input.yield(1)
    input.yield(2)
    input.finish()

    await fulfillment(of: [finished], timeout: 1.0)
  }

  func test_pipe_produces_stream_input_and_output_that_can_throw() async {
    let finished = expectation(description: "The stream has finished")

    // Given
    let (input, output) = AsyncThrowingStream<Int, Error>.pipe()

    Task {
      // Then
      var receivedElements = [Int]()
      do {
        for try await element in output {
          receivedElements.append(element)
        }
      } catch {
        XCTAssertEqual(receivedElements, [1, 2])
        XCTAssertEqual(error as? MockError, MockError(code: 1701))
      }
      finished.fulfill()
    }

    // When
    input.yield(1)
    input.yield(2)
    input.yield(with: .failure(MockError(code: 1701)))

    await fulfillment(of: [finished], timeout: 1.0)
  }
}
