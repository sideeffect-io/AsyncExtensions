//
//  AsyncScanSequenceTests.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

import AsyncExtensions
import XCTest

final class AsyncScanSequenceTests: XCTestCase {
  func testScan_applies_the_reducer_and_return_partial_results() async throws {
    let expectedResult = ["1", "12", "123", "1234", "12345"]
    var receivedResult = [String]()
    
    let sourceSequence = [1, 2, 3, 4, 5].async
    let reducer: @Sendable (String, Int) async -> String = { accumulator, nextValue in
      accumulator + "\(nextValue)"
    }
    
    let sut = sourceSequence.scan("", reducer)
    for try await element in sut {
      receivedResult.append(element)
    }
    
    XCTAssertEqual(receivedResult, expectedResult)
  }
  
  func testScan_finishes_when_task_is_cancelled() {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")
    
    let sourceSequence = [1, 2, 3, 4, 5].async
    let reducer: @Sendable (String, Int) async -> String = { accumulator, nextValue in
      accumulator + "\(nextValue)"
    }
    
    let sut = sourceSequence.scan("", reducer)
    
    let task = Task {
      var firstElement: String?
      for try await element in sut {
        firstElement = element
        canCancelExpectation.fulfill()
        wait(for: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement, "1")
      taskHasFinishedExpectation.fulfill()
    }
    
    wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task
    
    task.cancel()
    
    hasCancelExceptation.fulfill() // we can release the lock in the for loop
    
    wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }
}
