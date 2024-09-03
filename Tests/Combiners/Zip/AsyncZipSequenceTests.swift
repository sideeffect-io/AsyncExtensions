//
//  AsyncZipSequenceTests.swift
//
//
//  Created by Thibault Wittemberg on 14/01/2022.
//

@testable import AsyncExtensions
import XCTest

private struct TimedAsyncSequence<Element>: AsyncSequence, AsyncIteratorProtocol {
  typealias Element = Element
  typealias AsyncIterator = TimedAsyncSequence

  private let intervalInMills: UInt64
  private var iterator: Array<Element>.Iterator

  init(intervalInMills: UInt64, sequence: [Element]) {
    self.intervalInMills = intervalInMills
    self.iterator = sequence.makeIterator()
  }

  mutating func next() async -> Element? {
    try? await Task.sleep(nanoseconds: self.intervalInMills * 1_000_000)
    return self.iterator.next()
  }

  func makeAsyncIterator() -> AsyncIterator {
    self
  }
}

final class AsyncZipSequenceTests: XCTestCase {
  func testZip2_respects_chronology_and_ends_when_first_sequence_ends() async {
    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4])
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8", "9", "10"])

    let sut = zip(asyncSeq1, asyncSeq2)

    var receivedElements = [(Int, String)]()

    for await element in sut {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3, 4])
    XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8", "9"])
  }

  func testZip2_respects_chronology_and_ends_when_second_sequence_ends() async {
    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8"])

    let sut = zip(asyncSeq1, asyncSeq2)

    var receivedElements = [(Int, String)]()

    for await element in sut {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
    XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8"])
  }

  func testZip2_respects_returns_nil_pastEnd() async {
    let asyncSeq1 = AsyncLazySequence([1, 2, 3])
    let asyncSeq2 = AsyncLazySequence(["1", "2", "3"])

    let sut = zip(asyncSeq1, asyncSeq2)

    var receivedElements = [(Int, String)]()
    let iterator = sut.makeAsyncIterator()

    while let element = await iterator.next() {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
    XCTAssertEqual(receivedElements.map { $0.1 }, ["1", "2", "3"])

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func testZip2_propagates_error_when_first_fails() async throws {
    let mockError = MockError(code: Int.random(in: 0...100))

    let asyncSeq1 = AsyncFailSequence<String>( mockError)
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4])

    let sut = zip(asyncSeq1, asyncSeq2)
    let iterator = sut.makeAsyncIterator()

    do {
      while let element = try await iterator.next() {
        print(element)
      }
      XCTFail("The zipped sequence should fail")
    } catch {
      XCTAssertEqual(error as? MockError, mockError)
    }

    let pastFail = try await iterator.next()
    XCTAssertNil(pastFail)
  }

  func testZip2_propagates_error_when_second_fails() async throws {
    let mockError = MockError(code: Int.random(in: 0...100))

    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4])
    let asyncSeq2 = AsyncFailSequence<String>( mockError)

    let sut = zip(asyncSeq1, asyncSeq2)
    let iterator = sut.makeAsyncIterator()

    do {
      while let _ = try await iterator.next() {}
      XCTFail("The zipped sequence should fail")
    } catch {
      XCTAssertEqual(error as? MockError, mockError)
    }

    let pastFail = try await iterator.next()
    XCTAssertNil(pastFail)
  }

  func testZip2_finishes_when_task_is_cancelled() {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")

    let asyncSeq1 = AsyncLazySequence([1, 2, 3])
    let asyncSeq2 = AsyncLazySequence(["1", "2", "3"])

    let sut = zip(asyncSeq1, asyncSeq2)

    let task = Task {
      var firstElement: (Int, String)?
      for try await element in sut {
        firstElement = element
        canCancelExpectation.fulfill()
        await fulfillment(of: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement!.0, 1)
      XCTAssertEqual(firstElement!.1, "1")
      taskHasFinishedExpectation.fulfill()
    }

    wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

    task.cancel()

    hasCancelExceptation.fulfill() // we can release the lock in the for loop

    wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }
}

extension AsyncZipSequenceTests {
  func testZip3_respects_chronology_and_ends_when_first_sequence_ends() async throws {
    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3])
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8", "9", "10"])
    let asyncSeq3 = TimedAsyncSequence(intervalInMills: 30, sequence: [true, false, true, false, true])

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3)

    var receivedElements = [(Int, String, Bool)]()

    for try await element in sut {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
    XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8"])
    XCTAssertEqual(receivedElements.map { $0.2 }, [true, false, true])
  }

  func testZip3_respects_chronology_and_ends_when_second_sequence_ends() async throws {
    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8"])
    let asyncSeq3 = TimedAsyncSequence(intervalInMills: 30, sequence: [true, false, true, false, true])

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3)

    var receivedElements = [(Int, String, Bool)]()

    for try await element in sut {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
    XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8"])
    XCTAssertEqual(receivedElements.map { $0.2 }, [true, false, true])
  }

  func testZip3_respects_chronology_and_ends_when_third_sequence_ends() async throws {
    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: ["6", "7", "8", "9", "10"])
    let asyncSeq3 = TimedAsyncSequence(intervalInMills: 30, sequence: [true, false, true])

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3)

    var receivedElements = [(Int, String, Bool)]()

    for try await element in sut {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
    XCTAssertEqual(receivedElements.map { $0.1 }, ["6", "7", "8"])
    XCTAssertEqual(receivedElements.map { $0.2 }, [true, false, true])
  }

  func testZip3_respects_returns_nil_pastEnd() async {
    let asyncSeq1 = AsyncLazySequence([1, 2, 3])
    let asyncSeq2 = AsyncLazySequence(["1", "2", "3"])
    let asyncSeq3 = AsyncLazySequence([true, false, true])

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3)

    var receivedElements = [(Int, String, Bool)]()
    let iterator = sut.makeAsyncIterator()

    while let element = await iterator.next() {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements.map { $0.0 }, [1, 2, 3])
    XCTAssertEqual(receivedElements.map { $0.1 }, ["1", "2", "3"])
    XCTAssertEqual(receivedElements.map { $0.2 }, [true, false, true])

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func testZip3_propagates_error_when_first_fails() async throws {
    let mockError = MockError(code: Int.random(in: 0...100))

    let asyncSeq1 = AsyncFailSequence<String>( mockError)
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4])
    let asyncSeq3 = TimedAsyncSequence(intervalInMills: 5, sequence: ["1", "2", "3", "4"])

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3)
    let iterator = sut.makeAsyncIterator()

    do {
      while let _ = try await iterator.next() {}
      XCTFail("The zipped sequence should fail")
    } catch {
      XCTAssertEqual(error as? MockError, mockError)
    }

    let pastFail = try await iterator.next()
    XCTAssertNil(pastFail)
  }

  func testZip3_propagates_error_when_second_fails() async throws {
    let mockError = MockError(code: Int.random(in: 0...100))

    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4])
    let asyncSeq2 = AsyncFailSequence<String>( mockError)
    let asyncSeq3 = TimedAsyncSequence(intervalInMills: 5, sequence: ["1", "2", "3", "4"])

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3)
    let iterator = sut.makeAsyncIterator()

    do {
      while let _ = try await iterator.next() {}
      XCTFail("The zipped sequence should fail")
    } catch {
      XCTAssertEqual(error as? MockError, mockError)
    }

    let pastFail = try await iterator.next()
    XCTAssertNil(pastFail)
  }

  func testZip3_propagates_error_when_third_fails() async throws {
    let mockError = MockError(code: Int.random(in: 0...100))

    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4])
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 5, sequence: ["1", "2", "3", "4"])
    let asyncSeq3 = AsyncFailSequence<String>( mockError)

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3)
    let iterator = sut.makeAsyncIterator()

    do {
      while let _ = try await iterator.next() {}
      XCTFail("The zipped sequence should fail")
    } catch {
      XCTAssertEqual(error as? MockError, mockError)
    }

    let pastFail = try await iterator.next()
    XCTAssertNil(pastFail)
  }

  func testZip3_finishes_when_task_is_cancelled() {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")

    let asyncSeq1 = AsyncLazySequence([1, 2, 3])
    let asyncSeq2 = AsyncLazySequence(["1", "2", "3"])
    let asyncSeq3 = AsyncLazySequence([true, false, true])

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3)

    let task = Task {
      var firstElement: (Int, String, Bool)?
      for try await element in sut {
        firstElement = element
        canCancelExpectation.fulfill()
        await fulfillment(of: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement!.0, 1) // the AsyncSequence is cancelled having only emitted the first element
      XCTAssertEqual(firstElement!.1, "1")
      XCTAssertEqual(firstElement!.2, true)
      taskHasFinishedExpectation.fulfill()
    }

    wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

    task.cancel()

    hasCancelExceptation.fulfill() // we can release the lock in the for loop

    wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }
}

extension AsyncZipSequenceTests {
  func testZip_respects_chronology_and_ends_when_any_sequence_ends() async {
    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 50, sequence: [1, 2, 3, 4, 5])
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: [1, 2, 3])
    let asyncSeq3 = TimedAsyncSequence(intervalInMills: 30, sequence: [1, 2, 3, 4, 5])
    let asyncSeq4 = TimedAsyncSequence(intervalInMills: 5, sequence: [1, 2, 3])
    let asyncSeq5 = TimedAsyncSequence(intervalInMills: 20, sequence: [1, 2, 3, 4, 5])

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3, asyncSeq4, asyncSeq5)

    var receivedElements = [[Int]]()

    let iterator = sut.makeAsyncIterator()
    while let element = await iterator.next() {
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements.count, 3)
    XCTAssertEqual(receivedElements[0], [1, 1, 1, 1, 1])
    XCTAssertEqual(receivedElements[1], [2, 2, 2, 2, 2])
    XCTAssertEqual(receivedElements[2], [3, 3, 3, 3, 3])

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func testZip_propagates_error() async throws {
    let mockError = MockError(code: Int.random(in: 0...100))

    let asyncSeq1 = TimedAsyncSequence(intervalInMills: 5, sequence: [1, 2, 3, 4]).eraseToAnyAsyncSequence()
    let asyncSeq2 = TimedAsyncSequence(intervalInMills: 10, sequence: [1, 2, 3, 4]).eraseToAnyAsyncSequence()
    let asyncSeq3 = AsyncFailSequence<Int>( mockError).eraseToAnyAsyncSequence()
    let asyncSeq4 = TimedAsyncSequence(intervalInMills: 20, sequence: [1, 2, 3, 4]).eraseToAnyAsyncSequence()
    let asyncSeq5 = TimedAsyncSequence(intervalInMills: 15, sequence: [1, 2, 3, 4]).eraseToAnyAsyncSequence()

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3, asyncSeq4, asyncSeq5)
    let iterator = sut.makeAsyncIterator()

    do {
      while let _ = try await iterator.next() {}
      XCTFail("The zipped sequence should fail")
    } catch {
      XCTAssertEqual(error as? MockError, mockError)
    }

    let pastFail = try await iterator.next()
    XCTAssertNil(pastFail)
  }

  func testZip_finishes_when_task_is_cancelled() {
    let canCancelExpectation = expectation(description: "The first element has been emitted")
    let hasCancelExceptation = expectation(description: "The task has been cancelled")
    let taskHasFinishedExpectation = expectation(description: "The task has finished")

    let asyncSeq1 = AsyncLazySequence([1, 2, 3])
    let asyncSeq2 = AsyncLazySequence([1, 2, 3])
    let asyncSeq3 = AsyncLazySequence([1, 2, 3])
    let asyncSeq4 = AsyncLazySequence([1, 2, 3])
    let asyncSeq5 = AsyncLazySequence([1, 2, 3])

    let sut = zip(asyncSeq1, asyncSeq2, asyncSeq3, asyncSeq4, asyncSeq5)

    let task = Task {
      var firstElement: [Int]?
      for await element in sut {
        firstElement = element
        canCancelExpectation.fulfill()
        await fulfillment(of: [hasCancelExceptation], timeout: 5)
      }
      XCTAssertEqual(firstElement!, [1, 1, 1, 1, 1])
      taskHasFinishedExpectation.fulfill()
    }

    wait(for: [canCancelExpectation], timeout: 5) // one element has been emitted, we can cancel the task

    task.cancel()

    hasCancelExceptation.fulfill() // we can release the lock in the for loop

    wait(for: [taskHasFinishedExpectation], timeout: 5) // task has been cancelled and has finished
  }
}
