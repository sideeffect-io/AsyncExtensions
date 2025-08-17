//
//  AsyncTimerSequenceTests.swift
//  
//
//  Created by Thibault Wittemberg on 06/03/2022.
//

import AsyncExtensions
import XCTest

final class AsyncTimerSequenceTests: XCTestCase {
  func testTimer_finishes_when_task_is_cancelled() async {
    let canCancelExpectation = expectation(description: "the timer can be cancelled")
    let asyncSequenceHasFinishedExpectation = expectation(description: "The async sequence has finished")

    let sut = AsyncTimerSequence(priority: .userInitiated, every: .milliseconds(100))

    let task = Task {
      var index = 1
      for try await _ in sut {
        if index == 10 {
          canCancelExpectation.fulfill()
        }
        index += 1
      }
      asyncSequenceHasFinishedExpectation.fulfill()
    }

    await fulfillment(of: [canCancelExpectation], timeout: 5)

    task.cancel()

    await fulfillment(of: [asyncSequenceHasFinishedExpectation], timeout: 5)
  }
}
