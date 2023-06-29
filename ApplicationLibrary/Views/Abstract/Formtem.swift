import Foundation
import SwiftUI

public func FormView(@ViewBuilder content: () -> some View) -> some View {
    Form {
        content()
    }
    #if os(macOS)
    .formStyle(.grouped)
    #endif
}

public func FormTextItem(_ name: String, _ value: String) -> some View {
    HStack {
        Text(name)
        Spacer()
        Text(value)
            .multilineTextAlignment(.trailing)
            .font(Font.system(.caption, design: .monospaced))
            .textSelection(.enabled)
    }
}

public func FormItem(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    #if os(iOS)
        HStack {
            Text(title)
            Spacer()
            Spacer()
            content()
        }
    #else
        content()
    #endif
}
