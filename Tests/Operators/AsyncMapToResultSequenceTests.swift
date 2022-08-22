//
//  AsyncMapToResultSequenceTests.swift
//  
//
//  Created by Thibault Wittemberg on 28/08/2022.
//

import AsyncExtensions
import XCTest

final class AsyncMapToResultSequenceTests: XCTestCase {
  func test_mapToResult_maps_to_success_when_base_doesnt_throw() async throws {
    // Given
    let sut = AsyncJustSequence(1).mapToResult()
    var received: Result<Int, Error>?

    // When
    for await element in sut {
      received = element
    }

    // Then
    let receivedValue = try received?.get()
    XCTAssertEqual(receivedValue, 1)
  }

  func test_mapToResult_maps_to_failure_when_base_throws() async {
    // Given
    let sut = AsyncFailSequence<Int>(MockError(code: 1701)).mapToResult()
    var received: Result<Int, Error>?

    // When
    for await element in sut {
      received = element
    }

    // Then
    XCTAssertThrowsError(try received?.get()) { error in
      XCTAssertEqual(error as? MockError, MockError(code: 1701))
    }
  }
}
