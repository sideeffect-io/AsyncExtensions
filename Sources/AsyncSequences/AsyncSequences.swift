//
//  AsyncSequences.swift
//  
//
//  Created by Thibault Wittemberg on 31/12/2021.
//

/// Namespace for AsyncSequence creation functions
public enum AsyncSequences {}

public extension AsyncSequences {
    /// Represents a time interval in nanoseconds
    struct Interval: Equatable {
        let value: UInt64

        /// Represents an imediate time interval
        public static let immediate = Interval(value: 0)

        /// Represents a time interval in seconds
        public static func seconds(_ value: UInt64) -> Interval {
            Interval(value: value * 1_000_000_000)
        }

        /// Represents a time interval in milliseconds
        public static func milliSeconds(_ value: UInt64) -> Interval {
            Interval(value: value * 1_000_000)
        }

        /// Represents a time interval in nanoseconds
        public static func nanoSeconds(_ value: UInt64) -> Interval {
            Interval(value: value)
        }
    }
}
