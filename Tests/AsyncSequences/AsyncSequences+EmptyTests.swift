//
//  AsyncSequences+EmptyTests.swift
//  
//
//  Created by Thibault Wittemberg on 01/01/2022.
//

import AsyncExtensions
import XCTest

final class AsyncSequences_EmptyTests: XCTestCase {
    func testEmpty_returns_empty_asyncSequence() async throws {
        var hasElement = false

        let sut = AsyncSequences.Empty<Int>()
        for try await _ in sut {
            hasElement = true
        }

        XCTAssertFalse(hasElement)
    }
}
