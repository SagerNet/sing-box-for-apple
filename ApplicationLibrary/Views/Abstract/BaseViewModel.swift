import SwiftUI

@MainActor
open class BaseViewModel: ObservableObject {
    @Published public var alert: Alert?
    @Published public var isLoading = false

    public init() {}

    public func showError(_ error: Error) {
        alert = Alert(error)
    }

    public func execute(_ operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            alert = Alert(error)
        }
    }

    public func executeOnBackground(_ operation: @escaping @Sendable () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }
}
