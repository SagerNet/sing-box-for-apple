import Foundation

enum ProfileValidationGate {
    enum Event {
        case textChanged
        case debounceFired
        case popupClosed
    }

    enum Action: Equatable {
        case scheduleCheck(clearError: Bool)
        case runCheck
        case none
    }

    static func action(for event: Event, popupVisible: Bool) -> Action {
        switch event {
        case .textChanged:
            return .scheduleCheck(clearError: !popupVisible)
        case .debounceFired:
            return popupVisible ? .none : .runCheck
        case .popupClosed:
            return .scheduleCheck(clearError: false)
        }
    }
}
