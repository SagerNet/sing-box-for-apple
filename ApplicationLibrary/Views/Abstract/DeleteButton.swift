import Foundation
import SwiftUI

public struct DeleteButton<Label>: View where Label: View {
    private let action: () async -> Void
    private let label: Label

    @State private var performDelete = false
    @State private var timer: Timer?
    @State private var isLoading = false

    public init(action: @escaping () async -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    public var body: some View {
        Button(role: .destructive) {
            isLoading = true
            if let timer {
                timer.invalidate()
            }
            if !performDelete {
                performDelete = true
                timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
                    timer = nil
                    performDelete = false
                }
                isLoading = true
            } else {
                Task {
                    await action()
                    isLoading = false
                    performDelete = false
                }
            }
        } label: {
            if !performDelete {
                label
            } else {
                label.foregroundStyle(.red)
            }
        }
        .disabled(isLoading)
    }
}
