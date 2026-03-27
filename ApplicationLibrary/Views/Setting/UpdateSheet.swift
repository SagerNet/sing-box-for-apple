#if os(macOS)

    import AppKit
    import Library
    import MarkdownUI
    import SwiftUI

    public struct UpdateSheet: View {
        @ObservedObject var updateManager: UpdateManager
        @EnvironmentObject private var environments: ExtensionEnvironments

        public init(updateManager: UpdateManager) {
            self.updateManager = updateManager
        }

        public var body: some View {
            VStack(spacing: 16) {
                Text("Check Update")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("New version available: \(updateManager.updateInfo?.versionName ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let releaseNotes = updateManager.updateInfo?.releaseNotes, !releaseNotes.isEmpty {
                    ScrollView {
                        Markdown(GitHubEmoji.replaceShortcodes(in: releaseNotes))
                            .markdownTheme(.gitHub.text {
                                FontSize(10)
                            })
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                }

                if updateManager.isDownloading {
                    ProgressView(value: updateManager.downloadProgress)
                }

                HStack(spacing: 12) {
                    if let releaseURL = updateManager.updateInfo?.releaseURL,
                       let url = URL(string: releaseURL)
                    {
                        Button("View Release") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Spacer()

                    Button("Cancel", role: .cancel) {
                        updateManager.dismissUpdateSheet()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(updateManager.isDownloading)

                    Button("Update") {
                        Task {
                            await updateManager.downloadAndInstall(environments: environments)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(updateManager.isDownloading)
                }
            }
            .padding(20)
            .frame(minWidth: 480)
            .interactiveDismissDisabled(updateManager.isDownloading)
            .alert($updateManager.alert)
        }
    }

#endif
