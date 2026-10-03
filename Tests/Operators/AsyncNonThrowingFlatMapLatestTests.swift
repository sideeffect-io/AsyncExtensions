@testable import AsyncExtensions
import XCTest

final class AsyncNonThrowingFlatMapLatestTests: XCTestCase {
  func test_sequence_returning_transform_still_flattens_without_an_expected_type() async {
    let sequence = AsyncJustSequence(21).flatMapLatest { value async -> AsyncJustSequence<Int> in
      AsyncJustSequence(value * 2)
    }
    var values = [Int]()
    for await value in sequence { values.append(value) }
    XCTAssertEqual(values, [42])
  }

  func test_optional_scalar_nil_is_an_emitted_value() async {
    let sequence = AsyncJustSequence(21).flatMapLatest { _ async -> Int? in nil }
    var values = [Int?]()
    for await value in sequence { values.append(value) }
    XCTAssertEqual(values, [nil])
  }

  func test_new_input_cancels_previous_transform_and_discards_its_late_value() async {
    let source = AsyncBufferedChannel<Int>()
    let gate = JustFactoryGate(suspended: expectation(description: "First transformation suspended"))
    let cancelled = expectation(description: "First transformation cancelled")
    let receivedLatest = expectation(description: "Newest result received")
    let sequence = source.flatMapLatest { value async -> Int in
      if value == 1 {
        await withTaskCancellationHandler {
          await gate.wait()
        } onCancel: {
          cancelled.fulfill()
        }
      }
      return value
    }
    let task = Task {
      var values = [Int]()
      for await value in sequence {
        values.append(value)
        receivedLatest.fulfill()
      }
      return values
    }
    source.send(1)
    await fulfillment(of: [gate.suspended], timeout: 2)
    source.send(2)
    await fulfillment(of: [cancelled], timeout: 2)
    gate.open()
    await fulfillment(of: [receivedLatest], timeout: 2)
    source.finish()
    let values = await task.value
    XCTAssertEqual(values, [2])
  }

  func test_throwing_upstream_still_propagates_its_error() async {
    let sequence = AsyncFailSequence<Int>(MockError(code: 45)).flatMapLatest { value async -> Int in value }
    do {
      for try await _ in sequence { XCTFail("The upstream should fail") }
      XCTFail("Expected the upstream error")
    } catch {
      XCTAssertEqual(error as? MockError, MockError(code: 45))
    }
  }

  func test_nonthrowing_scalar_transform_can_be_iterated_without_try() async {
    let sequence = AsyncJustSequence(21).flatMapLatest { value async -> Int in value * 2 }
    var values = [Int]()
    for await value in sequence { values.append(value) }
    XCTAssertEqual(values, [42])
  }

  func test_nonthrowing_transform_can_return_results_without_terminating_the_sequence() async {
    let source = AsyncBufferedChannel<Int>()
    let sequence = source.flatMapLatest { value async -> Result<Int, MockError> in
      value == 1 ? .failure(MockError(code: 1)) : .success(value)
    }
    var iterator = sequence.makeAsyncIterator()
    source.send(1)
    let failure = await iterator.next()
    XCTAssertEqual(failure, .failure(MockError(code: 1)))
    source.send(2)
    let success = await iterator.next()
    XCTAssertEqual(success, .success(2))
    source.finish()
    let finished = await iterator.next()
    XCTAssertNil(finished)
  }
}
