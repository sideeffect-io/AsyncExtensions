import AsyncAlgorithms
import AsyncExtensions
import XCTest

final class AsyncAlgorithmsCompatibilityTests: XCTestCase {
  func test_async_extension_comes_from_async_algorithms() async {
    let sequence: AsyncSyncSequence<[Int]> = [1, 2, 3].async
    var received = [Int]()
    for await element in sequence {
      received.append(element)
    }
    XCTAssertEqual(received, [1, 2, 3])
  }

  func test_two_input_zip_comes_from_async_algorithms() async {
    let sequence = zip([1, 2].async, ["a", "b"].async)
    var received = [Tuple2<Int, String>]()
    for await element in sequence {
      received.append(Tuple2(element))
    }
    XCTAssertEqual(received, [Tuple2((1, "a")), Tuple2((2, "b"))])
  }

  func test_three_input_zip_comes_from_async_algorithms() async {
    let sequence = zip([1, 2].async, ["a", "b"].async, [true, false].async)
    var received = [Tuple3<Int, String, Bool>]()
    for await element in sequence {
      received.append(Tuple3(element))
    }
    XCTAssertEqual(received, [Tuple3((1, "a", true)), Tuple3((2, "b", false))])
  }

  func test_two_input_merge_comes_from_async_algorithms() async {
    let sequence = merge([1, 2].async, [3, 4].async)
    let appleSequence: AsyncMerge2Sequence<AsyncSyncSequence<[Int]>, AsyncSyncSequence<[Int]>> = sequence
    var received = [Int]()
    for await element in appleSequence {
      received.append(element)
    }
    XCTAssertEqual(received.sorted(), [1, 2, 3, 4])
  }

  func test_three_input_merge_comes_from_async_algorithms() async {
    let sequence = merge([1, 2].async, [3, 4].async, [5, 6].async)
    let appleSequence: AsyncMerge3Sequence<AsyncSyncSequence<[Int]>, AsyncSyncSequence<[Int]>, AsyncSyncSequence<[Int]>> = sequence
    var received = [Int]()
    for await element in appleSequence {
      received.append(element)
    }
    XCTAssertEqual(received.sorted(), [1, 2, 3, 4, 5, 6])
  }

  func test_four_input_zip_remains_available_from_async_extensions() async {
    let sequence = zip([1, 2].async, [10, 20].async, [100, 200].async, [1000, 2000].async)
    var received = [[Int]]()
    for await element in sequence {
      received.append(element)
    }
    XCTAssertEqual(received, [[1, 10, 100, 1000], [2, 20, 200, 2000]])
  }

  func test_four_input_merge_remains_available_from_async_extensions() async {
    let sequence = merge([1, 2].async, [3, 4].async, [5, 6].async, [7, 8].async)
    var received = [Int]()
    for await element in sequence {
      received.append(element)
    }
    XCTAssertEqual(received.sorted(), [1, 2, 3, 4, 5, 6, 7, 8])
  }
}
