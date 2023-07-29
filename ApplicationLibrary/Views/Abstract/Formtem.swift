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
        #if os(iOS) || os(macOS)
            .textSelection(.enabled)
        #endif
    }
}

public func FormItem(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    #if os(iOS) || os(tvOS)
        HStack {
            Text(title)
            Spacer()
            Spacer()
            content()
        }
    #elseif os(macOS)
        content()
    #endif
}
