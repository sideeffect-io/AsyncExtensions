//
//  ConcurrentAccessRegulator.swift
//  
//
//  Created by Thibault Wittemberg on 21/02/2022.
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

final class ConcurrentAccessRegulator<UpstreamAsyncSequence: AsyncSequence>: @unchecked Sendable {
    let upstreamAsyncSequence: UpstreamAsyncSequence
    var upstreamAsyncIterator: UpstreamAsyncSequence.AsyncIterator?
    let onNext: (UpstreamAsyncSequence.Element?) async -> Void
    let onError: (Error) async -> Void
    let onCancel: () async -> Void
    let gate = NonBlockingGate()

    init(
        _ upstreamAsyncSequence: UpstreamAsyncSequence,
        onNext: @escaping (UpstreamAsyncSequence.Element?) async -> Void,
        onError: @escaping (Error) async -> Void,
        onCancel: @escaping () async -> Void
    ) {
        self.upstreamAsyncSequence = upstreamAsyncSequence
        self.onNext = onNext
        self.onError = onError
        self.onCancel = onCancel
    }

    func requestNextIfAvailable() async {
        guard !Task.isCancelled else {
            await self.onCancel()
            return
        }

        guard await self.gate.lock() else {
            // not available ... see you next time
            // yield allows to promote other tasks to resume, giving a chance to free the lock
            await Task.yield()
            return
        }

        if self.upstreamAsyncIterator == nil {
            self.upstreamAsyncIterator = self.upstreamAsyncSequence.makeAsyncIterator()
        }

        do {
            let next = try await self.upstreamAsyncIterator?.next()
            await self.onNext(next)

            await self.gate.unlock()

            // yield allows to promote other tasks to resume, giving a chance to request a next element
            await Task.yield()
        } catch is CancellationError {
            await self.onCancel()
        } catch {
            await self.onError(error)
        }
    }
}
