//
//  AsyncWithLatestFrom2SequenceTests.swift
//
//
//  Created by Thibault Wittemberg on 11/09/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncWithLatestFrom2SequenceTests: XCTestCase {
  func test_withLatestFrom_uses_latest_element_from_others() async {
    // Timeline
    // base:      -0-----1      ---2      ---3      ---4      ---5      -x--|
    // other1:    ---a----      ----      -b--      -x--      ----      ----|
    // other2:    -----x--      -y--      ----      ----      -x--      ----|
    // expected:  -------(1,a,x)---(2,a,y)---(3,b,y)---(4,b,y)---(5,b,y)-x--|
    let baseHasProduced0 = expectation(description: "Base has produced 0")

    let other1HasProducedA = expectation(description: "Other has produced 'a'")
    let other1HasProducedB = expectation(description: "Other has produced 'b'")

    let other2HasProducedX = expectation(description: "Other has produced 'x'")
    let other2HasProducedY = expectation(description: "Other has produced 'y'")

    let base = AsyncBufferedChannel<Int>()
    let other1 = AsyncBufferedChannel<String>()
    let other2 = AsyncBufferedChannel<String>()

    var sequence = base.withLatest(from: other1, other2)
    // expectations that ensure that "others" has really delivered
    // their elements before requesting the next element from "base"
    sequence.onOther1Element = { @Sendable element in
      if element == "a" {
        other1HasProducedA.fulfill()
      }

      if element == "b" {
        other1HasProducedB.fulfill()
      }
    }

    sequence.onOther2Element = { @Sendable element in
      if element == "x" {
        other2HasProducedX.fulfill()
      }

      if element == "y" {
        other2HasProducedY.fulfill()
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
      await fulfillment(of: [baseHasProduced0], timeout: 1.0)
      other1.send("a")
      await fulfillment(of: [other1HasProducedA], timeout: 1.0)
      other2.send("x")
      await fulfillment(of: [other2HasProducedX], timeout: 1.0)
      base.send(1)
    }

    let element1 = await iterator.next()
    XCTAssertEqual(Tuple3(element1!), Tuple3((1, "a", "x")))

    Task {
      other2.send("y")
      await fulfillment(of: [other2HasProducedY], timeout: 1.0)
      base.send(2)
    }

    let element2 = await iterator.next()
    XCTAssertEqual(Tuple3(element2!), Tuple3((2, "a", "y")))

    Task {
      other1.send("b")
      await fulfillment(of: [other1HasProducedB], timeout: 1.0)
      base.send(3)
    }

    let element3 = await iterator.next()
    XCTAssertEqual(Tuple3(element3!), Tuple3((3, "b", "y")))

    Task {
      other1.finish()
      base.send(4)
    }

    let element4 = await iterator.next()
    XCTAssertEqual(Tuple3(element4!), Tuple3((4, "b", "y")))

    Task {
      other2.finish()
      base.send(5)
    }

    let element5 = await iterator.next()
    XCTAssertEqual(Tuple3(element5!), Tuple3((5, "b", "y")))

    base.finish()

    let element6 = await iterator.next()
    XCTAssertNil(element6)

    let pastEnd = await iterator.next()
    XCTAssertNil(pastEnd)
  }

  func test_withLatestFrom_throws_when_base_throws_and_pastEnd_is_nil() async throws {
    let base = [1, 2, 3]
    let other1 = Indefinite(value: "a")
    let other2 = Indefinite(value: "x")

    let sequence = base.async.map { try throwOn(1, $0) }.withLatest(from: other1.async, other2.async)
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

  func test_withLatestFrom_throws_when_other1_throws_and_pastEnd_is_nil() async throws {
    let base = Indefinite(value: 1)
    let other1 = AsyncThrowingBufferedChannel<String, Error>()
    let other2 = Indefinite(value: "x").async

    let sequence = base.async.withLatest(from: other1, other2)
    var iterator = sequence.makeAsyncIterator()

    other1.fail(MockError(code: 1701))

    do {
      var element: (Int, String, String)?
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

  func test_withLatestFrom_throws_when_other2_throws_and_pastEnd_is_nil() async throws {
    let base = Indefinite(value: 1)
    let other1 = Indefinite(value: "x").async
    let other2 = AsyncThrowingBufferedChannel<String, Error>()

    let sequence = base.async.withLatest(from: other1, other2)
    var iterator = sequence.makeAsyncIterator()

    other2.fail(MockError(code: 1701))

    do {
      var element: (Int, String, String)?
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
    let other1 = Indefinite(value: "a").async
    let other2 = Indefinite(value: "x").async

    let sequence = base.withLatest(from: other1, other2)

    let task = Task(priority: .high) {
      var iterator = sequence.makeAsyncIterator()

      var firstIteration = false
      var firstElement: (Int, String, String)?
      while let element = await iterator.next() {
        if !firstIteration {
          firstElement = element
          firstIteration = true
          iterated.fulfill()
        }
      }
      XCTAssertEqual(Tuple3(firstElement!), Tuple3((1, "a", "x")))

      finished.fulfill()
    }

    // ensure the other task actually starts
    await fulfillment(of: [iterated], timeout: 5.0)

    // cancellation should ensure the loop finishes
    // without regards to the remaining underlying sequence
    task.cancel()
    await fulfillment(of: [finished], timeout: 5.0)
  }
}
