@testable import AsyncExtensions
import Dispatch
import XCTest

final class ManagedCriticalStateTests: XCTestCase {
  func test_throwing_critical_region_preserves_changes_and_releases_lock() async {
    let state = ManagedCriticalState(0)
    XCTAssertThrowsError(try state.withCriticalRegion { value in
      value = 1
      throw MockError(code: 1701)
    }) { error in
      XCTAssertEqual(error as? MockError, MockError(code: 1701))
    }

    let reacquired = expectation(description: "Another thread can acquire the lock after a throw")
    DispatchQueue.global().async {
      XCTAssertEqual(state.criticalState, 1)
      state.apply(criticalState: 2)
      XCTAssertEqual(state.criticalState, 2)
      reacquired.fulfill()
    }
    await fulfillment(of: [reacquired], timeout: 2)
  }
}
