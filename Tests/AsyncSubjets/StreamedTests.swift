//
//  StreamedTests.swift
//  
//
//  Created by Thibault Wittemberg on 20/03/2022.
//

import AsyncExtensions
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif
import XCTest

final class StreamedTests: XCTestCase {
    @Streamed
    var sut: Int = 0

    func test_streamed_gets_and_sets_element() {
        XCTAssertEqual(sut, 0)
        let newValue = Int.random(in: 0...100)
        self.sut = newValue
        XCTAssertEqual(sut, newValue)
    }

    func test_streamed_projects_in_asyncSequence() {
        let firstElementIsReceivedExpectation = expectation(description: "The first element has been received")
        let fifthElementIsReceivedExpectation = expectation(description: "The fifth element has been received")

        let expectedElements = [0, 1, 2, 3, 4]
        let task = Task(priority: .high) {
            var receivedElements = [Int]()
            for try await element in self.$sut {
                receivedElements.append(element)

                if element == 0 {
                    firstElementIsReceivedExpectation.fulfill()
                }
                if element == 4 {
                    fifthElementIsReceivedExpectation.fulfill()
                    XCTAssertEqual(receivedElements, expectedElements)
                }
            }
        }

        wait(for: [firstElementIsReceivedExpectation], timeout: 1)

        sut = 1
        sut = 2
        sut = 3
        sut = 4

        wait(for: [fifthElementIsReceivedExpectation], timeout: 1)
        task.cancel()
    }
}
