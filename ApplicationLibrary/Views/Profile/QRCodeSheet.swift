import Foundation
import Libbox
import Library
import QRCode
import SwiftUI

private extension CGColor {
    static var labelColor: CGColor {
        #if canImport(UIKit)
            UIColor.label.cgColor
        #elseif canImport(AppKit)
            NSColor.labelColor.cgColor
        #endif
    }
}

@MainActor
public struct QRCodeContentView: View {
    private let profileName: String
    private let remoteURL: String

    public init(profileName: String, remoteURL: String) {
        self.profileName = profileName
        self.remoteURL = remoteURL
    }

    public var body: some View {
        VStack {
            Spacer()
            QRCodeViewUI(
                content: LibboxGenerateRemoteProfileImportLink(profileName, remoteURL),
                errorCorrection: .low,
                foregroundColor: .labelColor,
                backgroundColor: CGColor(gray: 1.0, alpha: 0.0),
                additionalQuietZonePixels: 4
            )
            #if os(macOS)
            .frame(minWidth: 300, minHeight: 300)
            #endif
            Spacer()
        }
        .padding()
    }
}

@MainActor
public struct QRCodeSheet: View {
    private let profileName: String
    private let remoteURL: String

    public init(profileName: String, remoteURL: String) {
        self.profileName = profileName
        self.remoteURL = remoteURL
    }

    public var body: some View {
        #if os(macOS)
            NavigationSheet {
                QRCodeContentView(profileName: profileName, remoteURL: remoteURL)
            }
            .frame(minWidth: 400, minHeight: 400)
        #elseif os(iOS) || os(tvOS)
            if #available(iOS 16.0, tvOS 17.0, *) {
                NavigationStackCompat {
                    QRCodeContentView(profileName: profileName, remoteURL: remoteURL)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            } else {
                NavigationStackCompat {
                    QRCodeContentView(profileName: profileName, remoteURL: remoteURL)
                }
            }
        #endif
    }
}

@MainActor
public struct URLQRCodeContentView: View {
    private let url: String

    public init(url: String) {
        self.url = url
    }

    public var body: some View {
        VStack {
            Spacer()
            QRCodeViewUI(
                content: url,
                errorCorrection: .low,
                foregroundColor: .labelColor,
                backgroundColor: CGColor(gray: 1.0, alpha: 0.0),
                additionalQuietZonePixels: 4
            )
            #if os(macOS)
            .frame(minWidth: 300, minHeight: 300)
            #endif
            Spacer()
        }
        .padding()
    }
}

@MainActor
public struct URLQRCodeSheet: View {
    private let url: String
    private let title: String

    public init(url: String, title: String) {
        self.url = url
        self.title = title
    }

    public var body: some View {
        #if os(macOS)
            NavigationSheet(title: title) {
                URLQRCodeContentView(url: url)
            }
            .frame(minWidth: 400, minHeight: 400)
        #elseif os(iOS) || os(tvOS)
            if #available(iOS 16.0, tvOS 17.0, *) {
                NavigationStackCompat {
                    URLQRCodeContentView(url: url)
                        .navigationTitle(title)
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            } else {
                NavigationStackCompat {
                    URLQRCodeContentView(url: url)
                        .navigationTitle(title)
                }
            }
        #endif
    }
}
