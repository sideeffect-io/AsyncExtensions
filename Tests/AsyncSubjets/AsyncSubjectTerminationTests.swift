@testable import AsyncExtensions
import XCTest

final class AsyncSubjectTerminationTests: XCTestCase {
  func test_throwing_passthrough_preserves_the_first_termination() async {
    await assertFirstTermination(makeSubject: { AsyncThrowingPassthroughSubject<Int, Error>() })
  }

  func test_throwing_current_value_preserves_the_first_termination() async {
    await assertFirstTermination(makeSubject: { AsyncThrowingCurrentValueSubject<Int, Error>(0) }, initial: [0])
  }

  func test_throwing_replay_preserves_the_first_termination() async {
    await assertFirstTermination(makeSubject: { AsyncThrowingReplaySubject<Int, Error>(bufferSize: 2) })
  }

  func test_throwing_passthrough_consumers_agree_on_concurrent_termination() async {
    await assertConcurrentTermination(makeSubject: { AsyncThrowingPassthroughSubject<Int, Error>() })
  }

  func test_throwing_current_value_consumers_agree_on_concurrent_termination() async {
    await assertConcurrentTermination(makeSubject: { AsyncThrowingCurrentValueSubject<Int, Error>(0) }, initial: [0])
  }

  func test_throwing_replay_consumers_agree_on_concurrent_termination() async {
    await assertConcurrentTermination(makeSubject: { AsyncThrowingReplaySubject<Int, Error>(bufferSize: 2) })
  }

  func test_current_value_ignores_sends_and_assignment_after_finish() {
    let subject = AsyncCurrentValueSubject<Int>(0)
    subject.send(1)
    subject.send(.finished)
    subject.send(2)
    subject.value = 3
    XCTAssertEqual(subject.value, 1)
  }

  func test_throwing_current_value_ignores_sends_and_assignment_after_termination() {
    for termination: Termination<Error> in [.finished, .failure(MockError(code: 1))] {
      let subject = AsyncThrowingCurrentValueSubject<Int, Error>(0)
      subject.send(1)
      subject.send(termination)
      subject.send(2)
      subject.value = 3
      XCTAssertEqual(subject.value, 1)
    }
  }

  private func assertFirstTermination<Subject: AsyncSubject>(
    makeSubject: () -> Subject,
    initial: [Int] = [],
    file: StaticString = #filePath,
    line: UInt = #line
  ) async where Subject.Element == Int, Subject.Failure == Error {
    let firstError = MockError(code: 1)
    let secondError = MockError(code: 2)
    let cases: [(Termination<Error>, Termination<Error>, MockError?)] = [
      (.finished, .finished, nil),
      (.finished, .failure(secondError), nil),
      (.failure(firstError), .finished, firstError),
      (.failure(firstError), .failure(secondError), firstError)
    ]
    for (firstTermination, secondTermination, expectedError) in cases {
      let subject = makeSubject()
      let existing = subject.makeAsyncIterator()
      subject.send(1)
      subject.send(firstTermination)
      subject.send(2)
      subject.send(secondTermination)
      let late = subject.makeAsyncIterator()
      let existingResult = await receive(existing, file: file, line: line)
      let lateResult = await receive(late, file: file, line: line)
      XCTAssertEqual(existingResult.values, initial + [1], file: file, line: line)
      XCTAssertEqual(existingResult.error, expectedError, file: file, line: line)
      XCTAssertEqual(lateResult.values, [], file: file, line: line)
      XCTAssertEqual(lateResult.error, expectedError, file: file, line: line)
    }
  }

  private func assertConcurrentTermination<Subject: AsyncSubject>(
    makeSubject: () -> Subject,
    initial: [Int] = [],
    file: StaticString = #filePath,
    line: UInt = #line
  ) async where Subject.Element == Int, Subject.Failure == Error {
    for competingTermination: Termination<Error> in [.finished, .failure(MockError(code: 2))] {
      for _ in 0..<200 {
        let subject = makeSubject()
        let existing = subject.makeAsyncIterator()
        subject.send(1)
        race({ subject.send(.failure(MockError(code: 1))) }, { subject.send(competingTermination) })
        let late = subject.makeAsyncIterator()
        let existingResult = await receive(existing, file: file, line: line)
        let lateResult = await receive(late, file: file, line: line)
        XCTAssertEqual(existingResult.values, initial + [1], file: file, line: line)
        XCTAssertEqual(lateResult.values, [], file: file, line: line)
        switch competingTermination {
          case .finished:
            XCTAssertTrue(existingResult.error == nil || existingResult.error == MockError(code: 1), file: file, line: line)
          case .failure:
            XCTAssertTrue(existingResult.error == MockError(code: 1) || existingResult.error == MockError(code: 2), file: file, line: line)
        }
        guard existingResult.error == lateResult.error else {
          return XCTFail("Existing and late consumers received different terminal outcomes", file: file, line: line)
        }
      }
    }
  }

  private func receive<Iterator: AsyncIteratorProtocol>(
    _ input: Iterator,
    file: StaticString,
    line: UInt
  ) async -> (values: [Int], error: MockError?) where Iterator.Element == Int {
    var iterator = input
    var values: [Int] = []
    do {
      while let value = try await iterator.next() { values.append(value) }
      return (values, nil)
    } catch {
      guard let error = error as? MockError else {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
        return (values, nil)
      }
      return (values, error)
    }
  }
}
