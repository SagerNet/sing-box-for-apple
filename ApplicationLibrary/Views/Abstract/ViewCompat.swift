import SwiftUI

public extension View {
    func onChangeCompat(of value: some Equatable, _ action: @escaping () -> Void) -> some View {
        onChange(of: value) { _ in
            action()
        }
    }

    func onChangeCompat<V: Equatable>(of value: V, _ action: @escaping (_ newValue: V) -> Void) -> some View {
        onChange(of: value, perform: action)
    }
}
