import Library
import SwiftUI

public struct ProfileOverrideView: View {
    @State private var isLoading = true
    @State private var excludeDefaultRoute = false
    @State private var autoRouteUseSubRangesByDefault = false

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
                    FormSection {
                        Toggle("Hide VPN Icon", isOn: $excludeDefaultRoute)
                            .onChangeCompat(of: excludeDefaultRoute) { newValue in
                                Task {
                                    await SharedPreferences.excludeDefaultRoute.set(newValue)
                                }
                            }
                    } footer: {
                        Text("Append `0.0.0.0/31` to `inet4_route_exclude_address` if not exists.")
                    }

                    FormSection {
                        Toggle("No Default Route", isOn: $autoRouteUseSubRangesByDefault)
                            .onChangeCompat(of: autoRouteUseSubRangesByDefault) { newValue in
                                Task {
                                    await SharedPreferences.autoRouteUseSubRangesByDefault.set(newValue)
                                }
                            }
                    } footer: {
                        Text("By default, segment routing is used in `auto_route` instead of global routing. If `*_<route_address/route_exclude_address>` exists in the configuration, this item will not take effect on the corresponding network. (commonly used to resolve HomeKit compatibility issues)")
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
        isLoading = false
    }
}
