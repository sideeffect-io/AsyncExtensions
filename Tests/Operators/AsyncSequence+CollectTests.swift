//
//  AsyncSequence+CollectTests.swift
//  
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

import AsyncExtensions
import XCTest

private class SpyAsyncSequence<Base: Sequence>: AsyncSequence, AsyncIteratorProtocol {
  typealias Element = Base.Element
  typealias AsyncIterator = SpyAsyncSequence<Base>

  private var baseIterator: Base.Iterator
  var emittedElements = [Base.Element]()

  init(base: Base) {
    self.baseIterator = base.makeIterator()
  }

  func next() async throws -> Element? {
    let nextElement = self.baseIterator.next()
    if let element = nextElement {
      self.emittedElements.append(element)
    }
    return nextElement
  }

  func makeAsyncIterator() -> AsyncIterator {
    self
  }
}

final class AsyncSequence_CollectTests: XCTestCase {
  func test_collect_iterates_over_the_asyncSequence_and_returns_elements_in_array() async throws {
    let expectedResult = [1, 2, 3, 4, 5]

    let sut = SpyAsyncSequence(base: [1, 2, 3, 4, 5])

    let elements = try await sut.collect()

    XCTAssertEqual(elements, expectedResult)
  }

  func test_collect_iterates_over_the_asyncSequence_and_gives_the_elements_to_the_closure() async throws {
    let expectedResult = [1, 2, 3, 4, 5]
    var receivedElements = [Int]()

    let sut = SpyAsyncSequence(base: [1, 2, 3, 4, 5])

    try await sut.collect { element in
      receivedElements.append(element)
    }

    XCTAssertEqual(receivedElements, expectedResult)
    XCTAssertEqual(sut.emittedElements, expectedResult)
  }
}
