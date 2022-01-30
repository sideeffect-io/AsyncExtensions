//
//  AsyncSequencesTests.swift
//  
//
//  Created by Thibault Wittemberg on 24/01/2022.
//

@testable import AsyncExtensions
import XCTest

final class AsyncSequencesTests: XCTestCase {
    func testSeconds_is_1_000_000_000_nano() {
        let sut = AsyncSequences.Interval.seconds(1)
        XCTAssertEqual(sut.value, 1_000_000_000)
    }

    func testMilliSeconds_is_1_000_000_nano() {
        let sut = AsyncSequences.Interval.milliSeconds(1)
        XCTAssertEqual(sut.value, 1_000_000)
    }

    func testNanoSeconds_is_1_nano() {
        let sut = AsyncSequences.Interval.nanoSeconds(1)
        XCTAssertEqual(sut.value, 1)
    }
}
