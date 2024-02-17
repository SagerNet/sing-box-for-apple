import Foundation
import SwiftUI

public struct SponsorsView: View {
    @Environment(\.openURL) private var openURL

    public init() {}
    public var body: some View {
        FormView {
            Section {
                EmptyView()
            } footer: {
                Text(
                    """
                    **If I’ve defended your modern life, please consider sponsoring me.**

                    _sing-box is completely free and open source, sponsorships to the developer are voluntary and you will not receive any digital content or services._
                    """)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            FormButton("GitHub Sponsor (recommended)") {
                openURL(URL(string: "https://github.com/sponsors/nekohasekai")!)
            }
            FormButton("Other methods") {
                openURL(URL(string: "https://sekai.icu/sponsors/")!)
            }
        }
        .navigationTitle("Sponsors")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
