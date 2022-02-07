//
//  SharedAsyncIterator.swift
//  
//
//  Created by Thibault Wittemberg on 23/01/2022.
//

actor NonBlockingGate {
    var isLockable = true

    func lock() -> Bool {
        defer { self.isLockable = false }
        let isLockable = self.isLockable
        return isLockable
    }

    func unlock() {
        self.isLockable = true
    }
}

actor FinishState {
    var finished = false

    func isFinished() -> Bool {
        self.finished
    }

    func setFinished() {
        self.finished = true
    }
}

enum SharedElement<Element> {
    case value(Element)
    case notAvailable
}

extension SharedElement: Equatable where Element: Equatable {}

/// Allows to request a next element in a concurrent context. If the iterator is still busy when requesting next, then it will respond
/// "notAvailable".
class SharedAsyncIterator<BaseAsyncIterator: AsyncIteratorProtocol>: AsyncIteratorProtocol {
    typealias Element = SharedElement<BaseAsyncIterator.Element>

    var iterator: BaseAsyncIterator
    let gate = NonBlockingGate()
    let finishState = FinishState()

    init(iterator: BaseAsyncIterator) {
        self.iterator = iterator
    }

    func isFinished() async -> Bool {
        await self.finishState.isFinished()
    }

    func next() async throws -> Element? {
        guard !Task.isCancelled else { return nil }
        guard await !self.finishState.isFinished() else { return nil }

        guard await self.gate.lock() else {
            // yield allows to promote other tasks to resume, giving a chance to free the lock
            await Task.yield()
            return .notAvailable
        }

        let next = try await self.iterator.next()

        await self.gate.unlock()
        // yield allows to promote other tasks to resume, giving a chance to not be notAvailable
        await Task.yield()

        if let nonNilNext = next {
            return .value(nonNilNext)
        }

        await self.finishState.setFinished()
        return nil
    }
}
