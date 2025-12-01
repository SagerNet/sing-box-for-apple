import SwiftUI

public struct AlertState: Equatable {
    public var title: String
    public var message: String
    public var primaryButton: ButtonState?
    public var secondaryButton: ButtonState?
    public var onDismiss: (() -> Void)?

    public struct ButtonState: Equatable {
        public var label: String
        public var role: ButtonRole?
        public var action: (() -> Void)?

        public init(label: String, role: ButtonRole? = nil, action: (() -> Void)? = nil) {
            self.label = label
            self.role = role
            self.action = action
        }

        public static func == (lhs: ButtonState, rhs: ButtonState) -> Bool {
            lhs.label == rhs.label && lhs.role == rhs.role
        }

        public static func `default`(_ label: String, action: (() -> Void)? = nil) -> ButtonState {
            ButtonState(label: label, action: action)
        }

        public static func cancel(_ label: String = String(localized: "Cancel"), action: (() -> Void)? = nil) -> ButtonState {
            ButtonState(label: label, role: .cancel, action: action)
        }

        public static func destructive(_ label: String, action: (() -> Void)? = nil) -> ButtonState {
            ButtonState(label: label, role: .destructive, action: action)
        }
    }

    public init(error: Error, dismiss: (() -> Void)? = nil) {
        self.init(errorMessage: error.localizedDescription, dismiss: dismiss)
    }

    public init(errorMessage: String, dismiss: (() -> Void)? = nil) {
        title = String(localized: "Error")
        message = errorMessage
        primaryButton = .default(String(localized: "Ok"), action: dismiss)
        secondaryButton = nil
        onDismiss = nil
    }

    public init(title: String, message: String, dismissButton: ButtonState? = nil) {
        self.title = title
        self.message = message
        primaryButton = dismissButton ?? .default(String(localized: "Ok"))
        secondaryButton = nil
        onDismiss = nil
    }

    public init(title: String, message: String, primaryButton: ButtonState, secondaryButton: ButtonState) {
        self.title = title
        self.message = message
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
        onDismiss = nil
    }

    public init(title: String, message: String, primaryButton: ButtonState, secondaryButton: ButtonState, onDismiss: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
        self.onDismiss = onDismiss
    }

    public static func == (lhs: AlertState, rhs: AlertState) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message &&
            lhs.primaryButton == rhs.primaryButton && lhs.secondaryButton == rhs.secondaryButton
    }
}

public extension View {
    @ViewBuilder
    func alert(_ binding: Binding<AlertState?>) -> some View {
        alert(
            binding.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { binding.wrappedValue != nil },
                set: { newValue, _ in
                    if !newValue {
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

    @ViewBuilder
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
