//
//  AsyncWithLatestFromSequenceTests.swift
//
//
//  Created by Thibault Wittemberg on 01/04/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncWithLatestFromSequenceTests: XCTestCase {
  func test_withLatestFrom_uses_latest_element_from_other() async {
    // Timeline
    // base:     -0---1    -2    -----3    ---4-----x--|
    // other:    ---a--    --    -b-c--    -x----------|
    // expected: -----(1,a)-(2,a)-----(3,c)---(4,c)-x--|
    let baseHasProduced0 = expectation(description: "Base has produced 0")

    let otherHasProducedA = expectation(description: "Other has produced 'a'")
    let otherHasProducedC = expectation(description: "Other has produced 'c'")

    let base = AsyncBufferedChannel<Int>()
    let other = AsyncBufferedChannel<String>()

    var sequence = base.withLatest(from: other)

    // expectations that ensure that "other" has really delivered
    // its elements before requesting the next element from "base"
    sequence.onOtherElement = { @Sendable element in
      if element == "a" {
        otherHasProducedA.fulfill()
      }

      if element == "c" {
        otherHasProducedC.fulfill()
      }
    }

    sequence.onBaseElement = { @Sendable element in
      if element == 0 {
        baseHasProduced0.fulfill()
      }
    }

    var iterator = sequence.makeAsyncIterator()

    Task {
      base.send(0)
      wait(for: [baseHasProduced0], timeout: 1.0)
      other.send("a")
      wait(for: [otherHasProducedA], timeout: 1.0)
      base.send(1)
    }

    let element1 = await iterator.next()
    XCTAssertEqual(Tuple2(element1!), Tuple2((1, "a")))

    base.send(2)

    let element2 = await iterator.next()
    XCTAssertEqual(Tuple2(element2!), Tuple2((2, "a")))

    Task {
      other.send("b")
      other.send("c")
      wait(for: [otherHasProducedC], timeout: 1.0)
      base.send(3)
    }

    let element3 = await iterator.next()
    XCTAssertEqual(Tuple2(element3!), Tuple2((3, "c")))

    other.finish()
    base.send(4)

    let element4 = await iterator.next()
    XCTAssertEqual(Tuple2(element4!), Tuple2((4, "c")))

    base.finish()

    let element5 = await iterator.next()
    XCTAssertNil(element5)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_withLatestFrom_throws_when_base_throws_and_pastEnd_is_nil() async throws {
    let base = [1, 2, 3]
    let other = Indefinite(value: "a")

    let sequence = base.async.map { try throwOn(1, $0) }.withLatest(from: other.async)
    var iterator = sequence.makeAsyncIterator()

    do {
      let value = try await iterator.next()
      XCTFail("got \(value as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? MockError, MockError(code: 1701))
    }

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_withLatestFrom_throws_when_other_throws_and_pastEnd_is_nil() async throws {
    let base = Indefinite(value: 1)
    let other = AsyncThrowingBufferedChannel<String, Error>()
    let sequence = base.async.withLatest(from: other)
    var iterator = sequence.makeAsyncIterator()

    other.fail(MockError(code: 1701))

    do {
      var element: (Int, String)?
      repeat {
        element = try await iterator.next()
      } while element == nil
      XCTFail("got \(element as Any) but expected throw")
    } catch {
      XCTAssertEqual(error as? MockError, MockError(code: 1701))
    }

    let pastEnd = try await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_withLatestFrom_finishes_loop_when_task_is_cancelled() async {
    let iterated = expectation(description: "The iteration has produced 1 element")
    let finished = expectation(description: "The iteration has finished")

    let base = Indefinite(value: 1).async
    let other = Indefinite(value: "a").async

    let sequence = base.withLatest(from: other)

    let task = Task(priority: .high) {
      var iterator = sequence.makeAsyncIterator()

      var firstIteration = false
      var firstElement: (Int, String)?
      while let element = await iterator.next() {
        if !firstIteration {
          firstElement = element
          firstIteration = true
          iterated.fulfill()
        }
      }
      XCTAssertEqual(Tuple2(firstElement!), Tuple2((1, "a")))
      finished.fulfill()
    }

    // ensure the other task actually starts
    wait(for: [iterated], timeout: 1.0)

    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    wait(for: [finished], timeout: 1.0)
  }
}
