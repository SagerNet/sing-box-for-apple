import Library
import SwiftUI

public struct ProfileOverrideView: View {
    @State private var isLoading = true
    @State private var excludeDefaultRoute = false
    @State private var autoRouteUseSubRangesByDefault = false
    @State private var excludeAPNsRoute = false

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
                    FormToggle("Hide VPN Icon", "Append `0.0.0.0/31` and `::/127` to `route_exclude_address` if not exists.", $excludeDefaultRoute) { newValue in
                        await SharedPreferences.excludeDefaultRoute.set(newValue)
                    }

                    FormToggle("No Default Route", """
                    By default, segment routing is used in `auto_route` instead of global routing.
                    If `*_<route_address/route_exclude_address>` exists in the configuration, this item will not take effect on the corresponding network (commonly used to resolve HomeKit compatibility issues).
                    """, $autoRouteUseSubRangesByDefault) { newValue in
                        await SharedPreferences.autoRouteUseSubRangesByDefault.set(newValue)
                    }

                    FormToggle("Exclude APNs Route", "Append `push.apple.com` to `bypass_domain`, and `17.0.0.0/8` to `route_exclude_address`.", $excludeAPNsRoute) { newValue in
                        await SharedPreferences.excludeAPNsRoute.set(newValue)
                    }

                    FormButton {
                        Task {
                            await SharedPreferences.resetProfileOverride()
                            isLoading = true
                        }
                    } label: {
                        Label("Reset", systemImage: "eraser.fill")
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Profile Override")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadSettings() async {
        excludeDefaultRoute = await SharedPreferences.excludeDefaultRoute.get()
        autoRouteUseSubRangesByDefault = await SharedPreferences.autoRouteUseSubRangesByDefault.get()
        excludeAPNsRoute = await SharedPreferences.excludeAPNsRoute.get()
        isLoading = false
    }
}
