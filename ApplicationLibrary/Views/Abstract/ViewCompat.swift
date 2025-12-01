import SwiftUI

public extension View {
    func onChangeCompat(of value: some Equatable, _ action: @escaping () -> Void) -> some View {
        onChange(of: value) { _ in
            action()
        }
    }

    func onChangeCompat<V>(of value: V, _ action: @escaping (_ newValue: V) -> Void) -> some View where V: Equatable {
        onChange(of: value, perform: action)
    }
}
