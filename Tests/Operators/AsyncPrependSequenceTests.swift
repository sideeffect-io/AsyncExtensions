//
//  AsyncPrependSequenceTests.swift
//  
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

import AsyncAlgorithms
import AsyncExtensions
import XCTest

final class AsyncPrependSequenceTests: XCTestCase {
  func testPrepend_prepends_an_element_to_the_source_asyncSequence() async throws {
    let expectedResult = [0, 1, 2, 3, 4, 5]
    var receivedResult = [Int]()
    
    let sut = [1, 2, 3, 4, 5].async
    
    let prependedSequence = sut.prepend(0)
    for try await element in prependedSequence {
      receivedResult.append(element)
    }
    
    XCTAssertEqual(receivedResult, expectedResult)
  }
  
  func testPrepend_finishes_when_task_is_cancelled() async {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")
    
    let sut = [1, 2, 3, 4, 5].async
    
    let prependedSequence = sut.prepend(0)
    
    let task = Task {
      var firstElement: Int?
      for try await element in prependedSequence {
        firstElement = element
        canCancelExpectation.fulfill()
        await fulfillment(of: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement, 0)
      taskHasFinishedExpectation.fulfill()
    }
    
    await fulfillment(of: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task
    
    task.cancel()
    
    hasCancelExceptation.fulfill() // we can release the lock in the for loop
    
    await fulfillment(of: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }
}
