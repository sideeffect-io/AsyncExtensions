//
//  Termination.swift
//  
//
//  Created by Thibault Wittemberg on 17/01/2022.
//

/// A signal that an async sequence doesn’t produce additional elements, either due to a normal ending or an error.
public enum Termination<Failure: Error>: Sendable {
  /// The sequence finished normally.
  case finished
  /// The sequence stopped emitting due to the indicated error.
  case failure(Failure)

  var isFinished: Bool {
    if case .finished = self {
      return true
    }
    return false
  }
}
