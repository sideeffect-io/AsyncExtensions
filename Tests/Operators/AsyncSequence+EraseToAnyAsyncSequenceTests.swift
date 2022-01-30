//
//  AsyncSequence+EraseToAnyAsyncSequenceTests.swift
//  
//
//  Created by Thibault Wittemberg on 04/01/2022.
//

import AsyncExtensions
import XCTest

final class AsyncSequence_EraseToAnyAsyncSequenceTests: XCTestCase {
    func testAnyAsyncSequence_gives_sames_values_as_original_sequence() async throws {
        let expectedValues = (0...4).map { _ in Int.random(in: 0...100) }
        var receivedValues = [Int]()

        let baseSequence = expectedValues.asyncElements
        let sut = baseSequence.eraseToAnyAsyncSequence()

        for try await element in sut {
            receivedValues.append(element)
        }

        XCTAssertEqual(receivedValues, expectedValues)
    }
}
