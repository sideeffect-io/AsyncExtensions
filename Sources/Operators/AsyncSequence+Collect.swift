//
//  AsyncSequence+Collect.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

public extension AsyncSequence {
    /// Iterates over each element of the AsyncSequence and give it to the block.
    /// - Parameter block: The closure to execute on each element of the async sequence.
    func collect(_ block: ((Element) -> Void)? = nil) async rethrows {
        for try await element in self {
            block?(element)
        }
    }
}
