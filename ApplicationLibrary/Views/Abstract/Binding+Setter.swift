import Foundation
import SwiftUI

public extension Binding {
    func withSetter(_ setter: @escaping (Value) -> Void) -> Binding<Value> {
        Binding {
            wrappedValue
        } set: { [setter] newValue, _ in
            setter(newValue)
        }
    }
}
