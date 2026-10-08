import Foundation
import Library
import SwiftUI

private enum OnDemandMode: String, CaseIterable, Identifiable {
    case disabled
    case alwaysOn
    case enabled

    var id: String {
        rawValue
    }

    var name: String {
        switch self {
        case .disabled: String(localized: "Disabled")
        case .alwaysOn: String(localized: "Always On")
        case .enabled: String(localized: "Enabled")
        }
    }

    var description: String {
        switch self {
        case .disabled: String(localized: "VPN will not connect automatically.")
        case .alwaysOn: String(localized: "Automatically connect VPN on any network.")
        case .enabled: String(localized: "Automatically connect or disconnect VPN based on rules.")
        }
    }
}

private extension OnDemandRuleAction {
    var systemImage: String {
        switch self {
        case .connect: "checkmark.circle.fill"
        case .disconnect: "xmark.circle.fill"
        case .evaluateConnection: "questionmark.circle.fill"
        case .ignore: "equal.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .connect: .green
        case .disconnect: .red
        case .evaluateConnection: .orange
        case .ignore: .gray
        }
    }
}

private extension EvaluateConnectionRuleAction {
    var actionDescription: String {
        switch self {
        case .connectIfNeeded: String(localized: "Connect VPN if the destination is not directly accessible.")
        case .neverConnect: String(localized: "Never connect VPN for matching domains.")
        }
    }
}

public struct OnDemandRulesView: View {
    @EnvironmentObject private var environments: ExtensionEnvironments
    @State private var isLoading = true
    @State private var alert: AlertState?
    @State private var mode: OnDemandMode = .disabled
    @State private var rules: [OnDemandRule] = []
    @State private var editingRule: OnDemandRule?
    @State private var isAddingRule = false
    @State private var loadTask: Task<Void, Never>?
    #if os(iOS)
        @State private var editMode: EditMode = .inactive
    #endif

    public init() {}
    public var body: some View {
        Group {
            if isLoading {
                ProgressView().onAppear {
                    loadTask = Task {
                        await loadSettings()
                    }
                }
            } else {
                FormView {
                    modePicker

                    if mode == .enabled {
                        rulesSection
                    }

                    resetButton
                }
            }
        }
        .navigationTitle("On Demand Rules")
        .onDisappear {
            loadTask?.cancel()
        }
        .alert($alert)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .disabled(rules.isEmpty)
                }
            }
            .environment(\.editMode, $editMode)
        #endif
        #if !os(tvOS)
        .platformSheet(isPresented: $isAddingRule) {
            OnDemandRuleEditView(rule: OnDemandRule(), isNew: true, onSave: addRule)
        }
        .platformSheet(item: $editingRule) { rule in
            OnDemandRuleEditView(rule: rule, isNew: false, onSave: updateRule) {
                deleteRule(rule)
            }
        }
        #endif
    }

    private var modePicker: some View {
        Section {
            FormPicker(
                String(localized: "Mode"),
                options: OnDemandMode.allCases.map { FormPickerOption($0, $0.name) },
                selection: $mode
            )
            .onChange(of: mode) { newValue in
                Task {
                    await saveMode(newValue)
                }
            }
        } footer: {
            Text(mode.description)
        }
    }

    private var rulesSection: some View {
        Section {
            ForEach(rules) { rule in
                ruleRow(rule)
            }
            .onMove { from, to in
                rules.move(fromOffsets: from, toOffset: to)
                Task {
                    await saveRules()
                }
            }
            .onDelete { offsets in
                rules.remove(atOffsets: offsets)
                Task {
                    await saveRules()
                }
            }
            #if os(tvOS)
                FormNavigationLink {
                    OnDemandRuleEditView(rule: OnDemandRule(), isNew: true, onSave: addRule)
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            #else
                FormButton {
                    isAddingRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            #endif
        } header: {
            Text("Rules")
        } footer: {
            if rules.isEmpty {
                Text("Without rules, the VPN connects on any network.")
            } else {
                Text("Rules are evaluated in order from top to bottom. The first matching rule determines the action.")
            }
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: OnDemandRule) -> some View {
        #if os(tvOS)
            FormNavigationLink {
                OnDemandRuleEditView(rule: rule, isNew: false, onSave: updateRule) {
                    deleteRule(rule)
                }
            } label: {
                ruleLabel(rule)
            }
        #else
            Button {
                editingRule = rule
            } label: {
                HStack {
                    ruleLabel(rule)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            #if os(macOS)
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    editingRule = rule
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button {
                    rules.move(id: rule.id, by: -1)
                    Task {
                        await saveRules()
                    }
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
                .disabled(rules.first?.id == rule.id)
                Button {
                    rules.move(id: rule.id, by: 1)
                    Task {
                        await saveRules()
                    }
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
                .disabled(rules.last?.id == rule.id)
                Divider()
                Button(role: .destructive) {
                    deleteRule(rule)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            #elseif os(iOS)
            .foregroundStyle(.primary)
            #endif
        #endif
    }

    private func ruleLabel(_ rule: OnDemandRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rule.action.systemImage)
                .font(.title2)
                .foregroundStyle(rule.action.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.action.name)
                Text(ruleSummary(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func ruleSummary(_ rule: OnDemandRule) -> String {
        var parts: [String] = []
        if rule.interfaceType != .any {
            parts.append(rule.interfaceType.name)
        }
        if !rule.ssidMatch.isEmpty {
            parts.append(String(localized: "SSID: \(listSummary(rule.ssidMatch))"))
        }
        if !rule.dnsSearchDomainMatch.isEmpty {
            parts.append(String(localized: "Search domain: \(listSummary(rule.dnsSearchDomainMatch))"))
        }
        if !rule.dnsServerAddressMatch.isEmpty {
            parts.append(String(localized: "DNS server: \(listSummary(rule.dnsServerAddressMatch))"))
        }
        if !rule.probeURL.isEmpty {
            parts.append(String(localized: "Probe: \(URL(string: rule.probeURL)?.host ?? rule.probeURL)"))
        }
        if rule.action == .evaluateConnection {
            let domains = rule.connectionRules.flatMap(\.matchDomains)
            if !domains.isEmpty {
                parts.append(String(localized: "Domains: \(listSummary(domains))"))
            }
        }
        if parts.isEmpty {
            return String(localized: "Any network")
        }
        return parts.joined(separator: " · ")
    }

    private var resetButton: some View {
        FormButton {
            Task {
                do {
                    try await SharedPreferences.resetOnDemandRules()
                    await updateService(.disabled)
                    isLoading = true
                } catch {
                    alert = AlertState(action: "reset on-demand rules", error: error)
                }
            }
        } label: {
            Label("Reset", systemImage: "eraser.fill")
        }
        .foregroundStyle(.red)
    }

    private func addRule(_ rule: OnDemandRule) {
        rules.append(rule)
        Task {
            await saveRules()
        }
    }

    private func updateRule(_ rule: OnDemandRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }
        rules[index] = rule
        Task {
            await saveRules()
        }
    }

    private func deleteRule(_ rule: OnDemandRule) {
        rules.removeAll { $0.id == rule.id }
        Task {
            await saveRules()
        }
    }

    private func saveMode(_ newMode: OnDemandMode) async {
        let alwaysOn = newMode == .alwaysOn
        let onDemandEnabled = newMode == .enabled
        await SharedPreferences.alwaysOn.set(alwaysOn)
        await SharedPreferences.onDemandEnabled.set(onDemandEnabled)
        await updateService(newMode)
    }

    private func updateService(_ newMode: OnDemandMode) async {
        guard let profile = environments.extensionProfile, newMode == .disabled || profile.status.isConnected else {
            return
        }
        do {
            let enabled = newMode != .disabled
            try await profile.updateOnDemand(enabled: enabled, useDefaultRules: newMode == .alwaysOn)
        } catch {
            alert = AlertState(action: "update on-demand rules", error: error)
        }
    }

    private func saveRules() async {
        await SharedPreferences.onDemandRules.set(rules)
        let savedRules = await SharedPreferences.onDemandRules.get()
        if savedRules != rules {
            alert = AlertState(errorMessage: String(localized: "Failed to save rules"))
            return
        }
        await updateService(mode)
    }

    private func loadSettings() async {
        let alwaysOn = await SharedPreferences.alwaysOn.get()
        let onDemandEnabled = await SharedPreferences.onDemandEnabled.get()
        if alwaysOn {
            mode = .alwaysOn
        } else if onDemandEnabled {
            mode = .enabled
        } else {
            mode = .disabled
        }
        rules = await SharedPreferences.onDemandRules.get()
        isLoading = false
    }
}

private struct OnDemandRuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: OnDemandRule
    private let isNew: Bool
    private let onSave: (OnDemandRule) -> Void
    private let onDelete: (() -> Void)?
    #if os(macOS)
        @State private var editingConnectionRule: EvaluateConnectionRule?
    #endif

    init(rule: OnDemandRule, isNew: Bool, onSave: @escaping (OnDemandRule) -> Void, onDelete: (() -> Void)? = nil) {
        _rule = State(initialValue: rule)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var canSave: Bool {
        guard isValidProbeURL(rule.probeURL), rule.dnsServerAddressMatch.allSatisfy(isValidIPAddress) else {
            return false
        }
        guard rule.action == .evaluateConnection else {
            return true
        }
        return rule.connectionRules.allSatisfy { domainRuleIssue($0) == nil }
    }

    var body: some View {
        Form {
            Section {
                FormPicker(
                    String(localized: "Action"),
                    options: OnDemandRuleAction.allCases.map { FormPickerOption($0, $0.name) },
                    selection: $rule.action
                )
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
            } footer: {
                Text(rule.action.actionDescription)
            }
            if rule.action == .evaluateConnection {
                domainRulesSection
            }
            conditionsSections
            #if os(tvOS)
                Section {
                    Button(isNew ? "Create" : "Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            #endif
            #if os(iOS) || os(tvOS)
                if let onDelete {
                    Section {
                        FormButton(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete Rule", systemImage: "trash.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            #endif
        }
        .navigationTitle(isNew ? "New Rule" : "Edit Rule")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(tvOS)
        .toolbar {
            #if os(macOS)
                if let onDelete {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            #endif
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Create" : "Save") {
                    save()
                }
                .disabled(!canSave)
            }
        }
        #endif
        #if os(macOS)
        .formStyle(.grouped)
        .platformSheet(item: $editingConnectionRule, size: .small) { connectionRule in
            if let index = rule.connectionRules.firstIndex(where: { $0.id == connectionRule.id }) {
                EvaluateConnectionRuleEditView(rule: $rule.connectionRules[index])
            }
        }
        #endif
    }

    private var domainRulesSection: some View {
        Section {
            ForEach($rule.connectionRules) { $connectionRule in
                Group {
                    #if os(macOS)
                        Button {
                            editingConnectionRule = connectionRule
                        } label: {
                            HStack {
                                domainRuleLabel(connectionRule)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    #else
                        FormNavigationLink {
                            EvaluateConnectionRuleEditView(rule: $connectionRule)
                        } label: {
                            domainRuleLabel(connectionRule)
                        }
                    #endif
                }
                .contextMenu {
                    Button {
                        rule.connectionRules.move(id: connectionRule.id, by: -1)
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(rule.connectionRules.first?.id == connectionRule.id)
                    Button {
                        rule.connectionRules.move(id: connectionRule.id, by: 1)
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .disabled(rule.connectionRules.last?.id == connectionRule.id)
                    Divider()
                    Button(role: .destructive) {
                        rule.connectionRules.removeAll { $0.id == connectionRule.id }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { from, to in
                rule.connectionRules.move(fromOffsets: from, toOffset: to)
            }
            .onDelete { offsets in
                rule.connectionRules.remove(atOffsets: offsets)
            }
            FormButton {
                rule.connectionRules.append(EvaluateConnectionRule())
            } label: {
                Label("Add Domain Rule", systemImage: "plus")
            }
        } header: {
            Text("Domain Rules")
        } footer: {
            Text("Each new connection is checked against these rules by its destination domain, from top to bottom.")
        }
    }

    private func domainRuleLabel(_ connectionRule: EvaluateConnectionRule) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(connectionRule.action.name)
            if let issue = domainRuleIssue(connectionRule) {
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(listSummary(normalizedList(connectionRule.matchDomains)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var conditionsSections: some View {
        Section {
            FormPicker(
                String(localized: "Interface Type"),
                options: OnDemandRuleInterfaceType.availableCases.map { FormPickerOption($0, $0.name) },
                selection: $rule.interfaceType
            )
            #if os(iOS)
            .pickerStyle(.menu)
            #endif
        } header: {
            Text("Conditions")
        } footer: {
            Text("All specified conditions must match for the rule to apply. Leave empty to match any network.")
        }
        Section {
            StringListRows(title: "SSID", prompt: "SSID", addTitle: "Add SSID", items: $rule.ssidMatch)
        } header: {
            Text("SSID")
        }
        Section {
            StringListRows(title: "Search Domain", prompt: "example.com", addTitle: "Add Search Domain", items: $rule.dnsSearchDomainMatch)
        } header: {
            Text("DNS Search Domains")
        } footer: {
            Text("Matches when the default search domain of the network is one of these.")
        }
        Section {
            StringListRows(title: "DNS Server", prompt: "IP address", addTitle: "Add DNS Server", items: $rule.dnsServerAddressMatch, isValid: isValidIPAddress)
        } header: {
            Text("DNS Servers")
        } footer: {
            if rule.dnsServerAddressMatch.allSatisfy(isValidIPAddress) {
                Text("Matches when every DNS server of the network is in this list.")
            } else {
                Text("Invalid IP address")
                    .foregroundStyle(.red)
            }
        }
        Section {
            ProbeURLField(url: $rule.probeURL)
        } footer: {
            if isValidProbeURL(rule.probeURL) {
                Text("Matches only when a request to this URL returns HTTP 200.")
            } else {
                Text("Only HTTP and HTTPS URLs are allowed")
                    .foregroundStyle(.red)
            }
        }
    }

    private func save() {
        var savedRule = rule
        savedRule.ssidMatch = normalizedList(rule.ssidMatch)
        savedRule.dnsSearchDomainMatch = normalizedList(rule.dnsSearchDomainMatch)
        savedRule.dnsServerAddressMatch = normalizedList(rule.dnsServerAddressMatch)
        savedRule.probeURL = rule.probeURL.trimmingCharacters(in: .whitespacesAndNewlines)
        savedRule.connectionRules = rule.connectionRules.map { connectionRule in
            var savedConnectionRule = connectionRule
            savedConnectionRule.matchDomains = normalizedList(connectionRule.matchDomains)
            savedConnectionRule.useDNSServers = normalizedList(connectionRule.useDNSServers)
            savedConnectionRule.probeURL = connectionRule.probeURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return savedConnectionRule
        }
        onSave(savedRule)
        dismiss()
    }
}

private struct EvaluateConnectionRuleEditView: View {
    #if os(macOS)
        @Environment(\.dismiss) private var dismiss
    #endif
    @Binding var rule: EvaluateConnectionRule

    var body: some View {
        Form {
            Section {
                FormPicker(
                    String(localized: "Action"),
                    options: EvaluateConnectionRuleAction.allCases.map { FormPickerOption($0, $0.name) },
                    selection: $rule.action
                )
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
            } footer: {
                Text(rule.action.actionDescription)
            }
            Section {
                StringListRows(title: "Domain", prompt: "example.com", addTitle: "Add Domain", items: $rule.matchDomains)
            } header: {
                Text("Domains")
            } footer: {
                Text("Matches when the destination host name ends with one of these domains.")
            }
            if rule.action == .connectIfNeeded {
                Section {
                    StringListRows(title: "DNS Server", prompt: "IP address", addTitle: "Add DNS Server", items: $rule.useDNSServers, isValid: isValidIPAddress)
                } header: {
                    Text("DNS Servers")
                } footer: {
                    if rule.useDNSServers.allSatisfy(isValidIPAddress) {
                        Text("DNS servers to use for resolving the destination. If resolution fails, VPN is started.")
                    } else {
                        Text("Invalid IP address")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    ProbeURLField(url: $rule.probeURL)
                } footer: {
                    if isValidProbeURL(rule.probeURL) {
                        Text("If set, a request is sent to this URL. If it doesn't return HTTP 200, VPN is started.")
                    } else {
                        Text("Only HTTP and HTTPS URLs are allowed")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle("Domain Rule")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if os(macOS)
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        #endif
    }
}

private struct StringListRows: View {
    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var value: String
    }

    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    let addTitle: LocalizedStringKey
    @Binding var items: [String]
    let isValid: (String) -> Bool
    @State private var rows: [Row]
    @FocusState private var focusedRow: UUID?

    init(title: LocalizedStringKey, prompt: LocalizedStringKey, addTitle: LocalizedStringKey, items: Binding<[String]>, isValid: @escaping (String) -> Bool = { _ in true }) {
        self.title = title
        self.prompt = prompt
        self.addTitle = addTitle
        _items = items
        self.isValid = isValid
        _rows = State(initialValue: items.wrappedValue.map { Row(value: $0) })
    }

    var body: some View {
        ForEach($rows) { $row in
            HStack {
                TextField(title, text: $row.value, prompt: Text(prompt))
                    .labelsHidden()
                    .foregroundColor(isValid(row.value) ? nil : .red)
                    .focused($focusedRow, equals: row.id)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                #endif
                Button {
                    rows.removeAll { $0.id == row.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .onDelete { offsets in
            rows.remove(atOffsets: offsets)
        }
        FormButton {
            if let emptyRow = rows.first(where: { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                focusedRow = emptyRow.id
                return
            }
            let newRow = Row(value: "")
            rows.append(newRow)
            DispatchQueue.main.async {
                focusedRow = newRow.id
            }
        } label: {
            Label(addTitle, systemImage: "plus.circle.fill")
        }
        .onChangeCompat(of: rows) { newValue in
            items = newValue.map(\.value)
        }
    }
}

private struct ProbeURLField: View {
    @Binding var url: String

    var body: some View {
        FormItem(String(localized: "Probe URL")) {
            TextField("Probe URL", text: $url, prompt: Text("Optional"))
                .multilineTextAlignment(.trailing)
            #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            #endif
        }
    }
}

private extension Array where Element: Identifiable {
    mutating func move(id: Element.ID, by offset: Int) {
        guard let index = firstIndex(where: { $0.id == id }), indices.contains(index + offset) else {
            return
        }
        swapAt(index, index + offset)
    }
}

private func listSummary(_ items: [String]) -> String {
    let summary = items.prefix(2).joined(separator: ", ")
    if items.count > 2 {
        return "\(summary) +\(items.count - 2)"
    }
    return summary
}

private func normalizedList(_ items: [String]) -> [String] {
    var result: [String] = []
    for item in items {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !result.contains(trimmed) {
            result.append(trimmed)
        }
    }
    return result
}

private func domainRuleIssue(_ rule: EvaluateConnectionRule) -> String? {
    if normalizedList(rule.matchDomains).isEmpty {
        return String(localized: "No domains")
    }
    guard rule.action == .connectIfNeeded else {
        return nil
    }
    if !rule.useDNSServers.allSatisfy(isValidIPAddress) {
        return String(localized: "Invalid IP address")
    }
    if !isValidProbeURL(rule.probeURL) {
        return String(localized: "Only HTTP and HTTPS URLs are allowed")
    }
    return nil
}

private func isValidProbeURL(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return true
    }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
        return false
    }
    return scheme == "http" || scheme == "https"
}

private func isValidIPAddress(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return true
    }
    var address = in_addr()
    var address6 = in6_addr()
    return trimmed.withCString { cString in
        inet_pton(AF_INET, cString, &address) == 1 || inet_pton(AF_INET6, cString, &address6) == 1
    }
}
