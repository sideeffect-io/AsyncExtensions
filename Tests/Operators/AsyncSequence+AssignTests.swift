//
//  AsyncSequence+AssignTests.swift
//  
//
//  Created by Thibault Wittemberg on 02/02/2022.
//

import AsyncExtensions
import XCTest

private class Root {
  var successiveValues = [String]()

  var property: String = "" {
    didSet {
      self.successiveValues.append(self.property)
    }
  }
}

final class AsyncSequence_AssignTests: XCTestCase {
  func testAssign_sets_elements_on_the_root() async throws {
    let root = Root()
    let sut = AsyncLazySequence(["1", "2", "3"])
    try await sut.assign(to: \.property, on: root)
    XCTAssertEqual(root.successiveValues, ["1", "2", "3"])
  }
}
