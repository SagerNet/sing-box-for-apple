import Foundation
import Library
import SwiftUI

@MainActor
public struct ServiceLogView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ServiceLogViewModel()

    private let logFont = Font.system(.caption, design: .monospaced)

    public init() {}

    public var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView().onAppear {
                    Task {
                        await viewModel.loadContent()
                    }
                }
            } else {
                if viewModel.isEmpty {
                    Text("Empty content")
                } else {
                    ScrollView {
                        Text(viewModel.content)
                            .font(logFont)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding()
                }
            }
        }
        .toolbar {
            if !viewModel.isEmpty {
                #if !os(tvOS)
                    ShareButtonCompat($viewModel.alert) {
                        Label("Export", systemImage: "square.and.arrow.up.fill")
                    } itemURL: {
                        try viewModel.generateShareFile()
                    }
                #endif
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteContent(dismiss: dismiss)
                    }
                } label: {
                    #if !os(tvOS)
                        Label("Delete", systemImage: "trash.fill")
                    #else
                        Image(systemName: "trash.fill")
                            .tint(.red)
                    #endif
                }
            }
        }
        .alertBinding($viewModel.alert)
        .navigationTitle("Service Log")
        #if os(tvOS)
            .focusable()
        #endif
    }
}
