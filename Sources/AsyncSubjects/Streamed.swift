//
//  Streamed.swift
//  
//
//  Created by Thibault Wittemberg on 20/03/2022.
//

/// A type that streams a property marked with an attribute as an AsyncSequence.
///
/// Streaming a property with the `@Streamed` attribute creates an AsyncSequence of this type.
/// You access the AsyncSequence with the `$` operator, as shown here:
///
/// class Weather {
///     @Streamed var temperature: Double
///     init(temperature: Double) {
///         self.temperature = temperature
///     }
/// }
///
/// let weather = Weather(temperature: 20)
/// Task {
///     for try await element in weather.$temperature {
///         print ("Temperature now: \(element)")
///     }
/// }
///
/// // ... later in the application flow
///
/// weather.temperature = 25
///
/// // Prints:
/// // Temperature now: 20.0
/// // Temperature now: 25.0
@propertyWrapper
public struct Streamed<Element> where Element: Sendable {
  let currentValue: AsyncCurrentValueSubject<Element>

  /// Creates the streamed instance with an initial wrapped value.
  ///
  /// Don't use this initializer directly. Instead, create a property with the `@Streamed` attribute, as shown here:
  ///
  ///     @Streamed var lastUpdated: Date = Date()
  ///
  /// - Parameter wrappedValue: The stream's initial value.
  public init(wrappedValue: Element) {
    self.currentValue = AsyncCurrentValueSubject<Element>(wrappedValue)
    self.wrappedValue = wrappedValue
  }

  public var wrappedValue: Element {
    willSet {
      self.currentValue.value = newValue
    }
  }

  /// The property for which this instance exposes an AsyncSequence.
  ///
  /// The ``Streamed/projectedValue`` is the property accessed with the `$` operator.
  public var projectedValue: AnyAsyncSequence<Element> {
    self.currentValue.eraseToAnyAsyncSequence()
  }
}

extension Streamed: Sendable where Element: Sendable {}
