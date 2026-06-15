#if JAILBREAK
    import Library
    import SwiftUI

    public struct JailbreakView: View {
        @State private var isLoading = true
        @State private var status: JailbreakHelperManager.Status = .notRunning

        public init() {}

        public var body: some View {
            FormView {
                if isLoading {
                    ProgressView()
                } else {
                    FormTextItem("Status", statusText)
                }
            }
            .navigationTitle("Jailbreak")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .onAppear { refresh() }
        }

        private var statusText: String {
            switch status {
            case .running:
                return String(localized: "Running")
            case .notRunning:
                return String(localized: "Not Running")
            }
        }

        private func refresh() {
            Task.detached {
                let current = JailbreakHelperManager.status()
                await MainActor.run {
                    status = current
                    isLoading = false
                }
            }
        }
    }
#endif
