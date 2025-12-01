import SwiftUI

@MainActor
open class BaseViewModel: ObservableObject {
    @Published public var alert: AlertState?
    @Published public var isLoading = false

    public init() {}

    public func showError(_ error: Error) {
        alert = AlertState(error: error)
    }

    public func execute(_ operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            alert = AlertState(error: error)
        }
    }

    public func executeOnBackground(_ operation: @escaping @Sendable () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            await MainActor.run {
                alert = AlertState(error: error)
            }
        }
    }
}
