import Foundation
import Library
import SwiftUI

public struct OnDemandRulesView: View {
    @State private var isLoading = true
    @State private var alwaysOn = false

    public init() {}
    public var body: some View {
        viewBuilder {
            if isLoading {
                ProgressView().onAppear {
                    Task.detached {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    FormToggle("Always On", """
                    Implement always-on via on-demand rules.

                    This should not be an intended use of the API, so you cannot disable VPN in system settings. To stop the service manually, use the in-app interface or simply delete the VPN profile.
                    """, $alwaysOn) { newValue in
                        await SharedPreferences.alwaysOn.set(newValue)
                    }

                    FormButton {
                        Task {
                            await SharedPreferences.resetOnDemandRules()
                            isLoading = true
                        }
                    } label: {
                        Label("Reset", systemImage: "eraser.fill")
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("On Demand Rules")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadSettings() async {
        alwaysOn = await SharedPreferences.alwaysOn.get()
        isLoading = false
    }
}
