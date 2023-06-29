import SwiftUI

public extension Binding {
    func unwrapped<T>(_ defaultValue: T) -> Binding<T> where Value == T? {
        Binding<T>(get: {
            wrappedValue ?? defaultValue
        }, set: { newValue in
            wrappedValue = newValue
        })
    }
}
