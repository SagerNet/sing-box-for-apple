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

public extension Binding where Value == Int32 {
    func stringBinding(defaultValue: Int32) -> Binding<String> {
        Binding<String> {
            var intValue = wrappedValue
            if intValue == 0 {
                intValue = defaultValue
            }
            return String(intValue)
        } set: { newValue in
            var newIntValue = Int32(newValue) ?? defaultValue
            if newIntValue == 0 {
                newIntValue = defaultValue
            }
            wrappedValue = newIntValue
        }
    }
}
