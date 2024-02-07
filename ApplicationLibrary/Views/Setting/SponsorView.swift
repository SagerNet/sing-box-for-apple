import Foundation
import StoreKit
import SwiftUI

public struct SponsorView: View {
    @Environment(\.openURL) private var openURL

    @State private var isLoading = true
    @State private var products: [Product] = []
    @State private var subscriptionError: Error?
    @State private var isPurchasing = false
    @State private var alert: Alert?

    public init() {}
    public var body: some View {
        FormView {
            Section {
                EmptyView()
            } footer: {
                Text("**If I’ve defended your modern life, please consider sponsoring me.**")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Without commission") {
                FormButton("GitHub Sponsor (recommended)") {
                    openURL(URL(string: "https://github.com/sponsors/nekohasekai")!)
                }
                FormButton("Other methods") {
                    openURL(URL(string: "https://sekai.icu/sponsor/")!)
                }
            }
            Section("Via App Store") {
                if isLoading {
                    ProgressView()
                        .onAppear {
                            Task.detached {
                                await loadProducts()
                            }
                        }
                } else if let subscriptionError {
                    Text("Sponsor via App Store not available: \(subscriptionError.localizedDescription)")
                } else {
                    ForEach(products, id: \.id) { it in
                        FormButton(it.displayName) {
                            isPurchasing = true
                            Task.detached {
                                do {
                                    let result = try await it.purchase()
                                    switch result {
                                    case .success:
                                        alert = Alert(title: Text("Success"), message: Text("Thank u."))
                                    case .pending:
                                        break
                                    case .userCancelled:
                                        break
                                    }
                                } catch {
                                    alert = Alert(error)
                                }
                                isPurchasing = false
                            }
                        }
                        .disabled(isPurchasing)
                    }
                }
            }
        }
        .alertBinding($alert)
        .navigationTitle("Sponsor")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func loadProducts() async {
        defer {
            isLoading = false
        }
        do {
            let productIds = ["sponsor_1_1", "sponsor_10", "sponsor_100"]
            products = try await Product.products(for: productIds)
        } catch {
            subscriptionError = error
        }
    }
}
