//
//  AsyncSubject.swift
//  
//
//  Created by Thibault Wittemberg on 08/01/2022.
//

#if swift(>=5.7)
public protocol AsyncSubjectable<Element>: AnyObject, AsyncSequence, Sendable where AsyncIterator: AsyncSubjectIterator {
    func send(_ element: Element)
}

public protocol AsyncSubjectTerminable {
    associatedtype Failure: Error

    func send(_ termination: Termination<Failure>)
}

public typealias AsyncSubject = AsyncSubjectable & AsyncSubjectTerminable
#else
public protocol AsyncSubject: AnyObject, AsyncSequence, Sendable where AsyncIterator: AsyncSubjectIterator {
  associatedtype Failure: Error

  func send(_ element: Element)
  func send(_ termination: Termination<Failure>)
}
#endif

public protocol AsyncSubjectIterator: AsyncIteratorProtocol, Sendable {
  var hasBufferedElements: Bool { get }
}

/// A consumer's place in a subject, which it leaves when the last copy of its iterator is
/// released. An iteration left early, by `break`, `return` or a throw from its own body, never
/// has its `next()` cancelled or finished, and would otherwise stay registered, buffering every
/// element sent from then on.
final class AsyncSubjectRegistration: Sendable {
  private let unregister: @Sendable () -> Void

  init(_ unregister: @escaping @Sendable () -> Void) {
    self.unregister = unregister
  }

  deinit {
    unregister()
  }
}
