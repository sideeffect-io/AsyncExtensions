//
//  AsyncEmptySequenceTests.swift
//  
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

import AsyncExtensions
import XCTest

final class AsyncEmptySequenceTests: XCTestCase {
  func test_AsyncEmptySequence_immediately_resumes() async throws {
    var hasElement = false

    let sut = AsyncEmptySequence<Int>()
    for try await _ in sut {
      hasElement = true
    }

    XCTAssertFalse(hasElement)
  }
}
