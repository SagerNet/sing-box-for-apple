import Foundation
import SwiftUI

public extension Alert {
    init(_ error: Error, _ dismissAction: (() -> Void)? = nil) {
        self.init(
            errorMessage: error.localizedDescription,
            dismissAction
        )
    }

    init(errorMessage: String, _ dismissAction: (() -> Void)? = nil) {
        self.init(
            title: Text("Error"),
            message: Text(errorMessage),
            dismissButton: .default(Text("Ok")) {
                dismissAction?()
            }
        )
    }
}

public extension View {
    func alertBinding(_ binding: Binding<Alert?>) -> some View {
        alert(isPresented: Binding(get: {
            binding.wrappedValue != nil
        }, set: { newValue, _ in
            if !newValue {
                binding.wrappedValue = nil
            }
        })) {
            binding.wrappedValue!
        }
    }

    func alertBinding(_ binding: Binding<Alert?>, _ isLoading: Binding<Bool>) -> some View {
        alert(isPresented: Binding(get: {
            binding.wrappedValue != nil
        }, set: { newValue, _ in
            if !newValue, !isLoading.wrappedValue {
                binding.wrappedValue = nil
            }
        })) {
            binding.wrappedValue!
        }
    }
}
