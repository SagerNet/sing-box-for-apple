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
    #if os(iOS)
        HStack {
            Text(title)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            Spacer()
            content()
        }
    #elseif os(tvOS)
        HStack {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            Spacer()
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .layoutPriority(1)
        }
    #elseif os(macOS)
        content()
    #endif
}

public func FormToggle(_ titleKey: LocalizedStringKey, _ subtitleKey: LocalizedStringKey, _ isOn: Binding<Bool>, _ action: @escaping (_ newValue: Bool) async -> Void) -> some View {
    #if os(macOS)
        Toggle(isOn: isOn) {
            VStack(alignment: .leading) {
                Text(titleKey)
                Spacer()
                Text(subtitleKey)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .onChangeCompat(of: isOn.wrappedValue) { newValue in
            Task {
                await action(newValue)
            }
        }
    #else
        Section {
            Toggle(titleKey, isOn: isOn)
                .onChangeCompat(of: isOn.wrappedValue) { newValue in
                    Task {
                        await action(newValue)
                    }
                }
        } footer: {
            Text(subtitleKey)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    #endif
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
                            .tint(.accentColor)
                    }
                }
        }, label: label)
    #endif
}
