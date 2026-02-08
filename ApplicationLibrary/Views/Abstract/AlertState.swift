import Library
@_exported import struct Library.AlertState
import SwiftUI

public extension View {
    func alert(_ binding: Binding<AlertState?>, isLoading: Binding<Bool>) -> some View {
        alert(
            binding.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { binding.wrappedValue != nil },
                set: { newValue, _ in
                    if !newValue, !isLoading.wrappedValue {
                        binding.wrappedValue?.onDismiss?()
                        binding.wrappedValue = nil
                    }
                }
            ),
            presenting: binding.wrappedValue
        ) { alertState in
            if let secondary = alertState.secondaryButton {
                Button(role: alertState.primaryButton?.role) {
                    alertState.primaryButton?.action?()
                } label: {
                    Text(alertState.primaryButton?.label ?? "Ok")
                }
                Button(role: secondary.role) {
                    secondary.action?()
                } label: {
                    Text(secondary.label)
                }
            } else if let primary = alertState.primaryButton {
                Button(role: primary.role) {
                    primary.action?()
                } label: {
                    Text(primary.label)
                }
            }
        } message: { alertState in
            Text(alertState.message)
        }
    }
}
