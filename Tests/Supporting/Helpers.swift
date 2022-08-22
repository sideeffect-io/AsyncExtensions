//
//  Helpers.swift
//  
//
//  Created by Thibault Wittemberg on 11/09/2022.
//

struct Indefinite<Element: Sendable>: Sequence, IteratorProtocol, Sendable {
  let value: Element

  func next() -> Element? {
    return value
  }

  func makeIterator() -> Indefinite<Element> {
    self
  }
}

func throwOn<T: Equatable>(_ toThrowOn: T, _ value: T) throws -> T {
  if value == toThrowOn {
    throw MockError(code: 1701)
  }
  return value
}

struct MockError: Error, Equatable {
  let code: Int
}

struct Tuple2<T1: Equatable, T2: Equatable>: Equatable {
  let value1: T1
  let value2: T2

  init(_ values: (T1, T2)) {
    self.value1 = values.0
    self.value2 = values.1
  }
}

struct Tuple3<T1: Equatable, T2: Equatable, T3: Equatable>: Equatable {
  let value1: T1
  let value2: T2
  let value3: T3

  init(_ values: (T1, T2, T3)) {
    self.value1 = values.0
    self.value2 = values.1
    self.value3 = values.2
  }
}
