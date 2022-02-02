//
//  AsyncSequence+Assign.swift
//  
//
//  Created by Thibault Wittemberg on 02/02/2022.
//

public extension AsyncSequence {
    /// Assigns each element from the async sequence to a property on an object.
    ///
    /// ```
    /// class Root {
    ///     var property: String = ""
    /// }
    ///
    /// let root = Root()
    /// let fromSequence = AsyncSequences.From(["1", "2", "3"])
    /// try await fromSequence.assign(to: \.property, on: root) // will set the property value to "1", "2", "3"
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: A key path that indicates the property to assign.
    ///   - object: The object that contains the property.
    func assign<Root>(to keyPath: ReferenceWritableKeyPath<Root, Self.Element>, on object: Root) async throws {
        for try await element in self {
            object[keyPath: keyPath] = element
        }
    }
}
