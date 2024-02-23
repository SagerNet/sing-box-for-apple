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

public func FormTextItem(_ name: LocalizedStringKey, _ value: String) -> some View {
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

public func FormTextItem(_ name: LocalizedStringKey, _ systemImage: String, @ViewBuilder _ value: () -> some View) -> some View {
    HStack {
        Label(name, systemImage: systemImage)
        Spacer()
        value()
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
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            Spacer()
            content()
        }
    #elseif os(macOS)
        content()
    #endif
}

public func FormSection(@ViewBuilder content: () -> some View, @ViewBuilder footer: () -> some View) -> some View {
    Section {
        content()
    } footer: {
        footer()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public func FormButton(action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
    Button(action: action, label: label)
    #if os(macOS)
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
    #endif
}

public func FormButton(_ titleKey: some StringProtocol, action: @escaping () -> Void) -> some View {
    Button(titleKey, action: action)
    #if os(macOS)
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
    #endif
}

public func FormButton(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
    Button(role: role, action: action, label: label)
    #if os(macOS)
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
    #endif
}

public func FormNavigationLink(@ViewBuilder destination: () -> some View, @ViewBuilder label: () -> some View) -> some View {
    #if !os(tvOS)
        return NavigationLink(destination: destination, label: label)
    #else
        return NavigationLink(destination: {
            destination()
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        BackButton()
                    }
                }
        }, label: label)
    #endif
}
