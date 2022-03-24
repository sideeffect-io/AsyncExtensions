//
//  AsyncSequence+MapErrorTests.swift
//  
//
//  Created by JCSooHwanCho on 2022/03/24.
//

import AsyncExtensions
import XCTest

private struct CustomError: Error, Equatable { }

final class AsyncSequence_MapErrorTests: XCTestCase {
    func testMapError_with_CustomError() async throws {
        let failSequence = AsyncSequences.Fail<Int>(error: NSError(domain: "", code: 1))

        do {
            for try await _ in failSequence.mapError({ _ in CustomError() }) {
                XCTFail()
            }
        } catch {
            XCTAssertEqual(error as! CustomError, CustomError())
        }
    }

    func testMappError_doesnot_affect_on_normal_finis() async throws {
        let intSequence = (1...5).asyncElements

        let reduced = try await intSequence
            .mapError { _ in CustomError() }
            .reduce(into: 0, +=)

        XCTAssertEqual(reduced, 15)
    }
}
