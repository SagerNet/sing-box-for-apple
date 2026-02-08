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
            OnDemandRuleEditView(rule: OnDemandRule(), isNew: true) { newRule in
                rules.append(newRule)
                Task {
                    await saveRules()
                }
            }
        }
        .platformSheet(item: $editingRule) { rule in
            OnDemandRuleEditView(rule: rule, isNew: false) { updatedRule in
                if let index = rules.firstIndex(where: { $0.id == updatedRule.id }) {
                    rules[index] = updatedRule
                    Task {
                        await saveRules()
                    }
                }
            }
        }
        #endif
    }

    private var modePicker: some View {
        Section {
            Picker("Mode", selection: $mode) {
                ForEach(OnDemandMode.allCases) { m in
                    Text(m.name).tag(m)
                }
            }
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
            if rules.isEmpty {
                Text("Empty rules")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
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
            }
        } header: {
            HStack {
                Text("Rules")
                Spacer()
                #if os(tvOS)
                    FormNavigationLink {
                        OnDemandRuleEditView(rule: OnDemandRule(), isNew: true) { newRule in
                            rules.append(newRule)
                            Task {
                                await saveRules()
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                #else
                    Button {
                        isAddingRule = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                #endif
            }
        } footer: {
            Text("Rules are evaluated in order from top to bottom. The first matching rule determines the action.")
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: OnDemandRule) -> some View {
        #if os(tvOS)
            FormNavigationLink {
                OnDemandRuleEditView(rule: rule, isNew: false) { updatedRule in
                    if let index = rules.firstIndex(where: { $0.id == updatedRule.id }) {
                        rules[index] = updatedRule
                        Task {
                            await saveRules()
                        }
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.action.name)
                        .fontWeight(.medium)
                    Text(ruleDescription(rule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        #else
            Button {
                editingRule = rule
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.action.name)
                            .fontWeight(.medium)
                        Text(ruleDescription(rule))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #elseif os(iOS)
            .foregroundStyle(.primary)
            #endif
        #endif
    }

    private func ruleDescription(_ rule: OnDemandRule) -> String {
        var parts: [String] = []

        if rule.interfaceType != .any {
            parts.append(rule.interfaceType.name)
        }

        if !rule.ssidMatch.isEmpty {
            let ssids = rule.ssidMatch.prefix(2).joined(separator: ", ")
            if rule.ssidMatch.count > 2 {
                parts.append("SSID: \(ssids) +\(rule.ssidMatch.count - 2)")
            } else {
                parts.append("SSID: \(ssids)")
            }
        }

        if !rule.dnsSearchDomainMatch.isEmpty {
            parts.append("DNS Domain")
        }

        if !rule.dnsServerAddressMatch.isEmpty {
            parts.append("DNS Server")
        }

        if !rule.probeURL.isEmpty {
            parts.append("Probe URL")
        }

        if rule.action == .evaluateConnection, !rule.connectionRules.isEmpty {
            parts.append("\(rule.connectionRules.count) connection rule(s)")
        }

        if parts.isEmpty {
            return "All networks"
        }
        return parts.joined(separator: " · ")
    }

    private var resetButton: some View {
        FormButton {
            Task {
                do {
                    try await SharedPreferences.resetOnDemandRules()
                    await updateService()
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

    private func saveMode(_ newMode: OnDemandMode) async {
        let alwaysOn = newMode == .alwaysOn
        let onDemandEnabled = newMode == .enabled
        await SharedPreferences.alwaysOn.set(alwaysOn)
        await SharedPreferences.onDemandEnabled.set(onDemandEnabled)
        await updateService()
    }

    private func updateService() async {
        guard let profile = environments.extensionProfile, profile.status.isConnected else {
            return
        }
        do {
            let enabled = mode != .disabled
            try await profile.updateOnDemand(enabled: enabled, useDefaultRules: mode == .alwaysOn)
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
        await updateService()
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
    private let onSave: (OnDemandRule) -> Void
    private let isNew: Bool

    @State private var editingConnectionRule: EvaluateConnectionRule?
    @State private var isAddingConnectionRule = false

    private var isProbeURLValid: Bool {
        guard !rule.probeURL.isEmpty else { return true }
        guard let url = URL(string: rule.probeURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return true
    }

    init(rule: OnDemandRule, isNew: Bool, onSave: @escaping (OnDemandRule) -> Void) {
        _rule = State(initialValue: rule)
        self.onSave = onSave
        self.isNew = isNew
    }

    var body: some View {
        Form {
            actionSection
            conditionsSection
            if rule.action == .evaluateConnection {
                connectionRulesSection
            }
            #if os(tvOS)
                Section {
                    Button(isNew ? "Create" : "Save") {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(!isProbeURLValid)
                }
            #endif
        }
        .navigationTitle(isNew ? "New Rule" : "Edit Rule")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(tvOS)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Create" : "Save") {
                    onSave(rule)
                    dismiss()
                }
                .disabled(!isProbeURLValid)
            }
        }
        #endif
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .platformSheet(isPresented: $isAddingConnectionRule, size: .small) {
            EvaluateConnectionRuleEditView(rule: EvaluateConnectionRule()) { newRule in
                rule.connectionRules.append(newRule)
            }
        }
        .platformSheet(item: $editingConnectionRule, size: .small) { connRule in
            EvaluateConnectionRuleEditView(rule: connRule) { updatedRule in
                if let index = rule.connectionRules.firstIndex(where: { $0.id == updatedRule.id }) {
                    rule.connectionRules[index] = updatedRule
                }
            }
        }
    }

    private var actionSection: some View {
        Section {
            Picker("Action", selection: $rule.action) {
                ForEach(OnDemandRuleAction.allCases) { action in
                    Text(action.name).tag(action)
                }
            }
            #if os(iOS)
            .pickerStyle(.menu)
            #endif

            Picker("Interface Type", selection: $rule.interfaceType) {
                ForEach(OnDemandRuleInterfaceType.availableCases, id: \.self) { type in
                    Text(type.name).tag(type)
                }
            }
            #if os(iOS)
            .pickerStyle(.menu)
            #endif
        } header: {
            Text("Action")
        } footer: {
            Text(rule.action.actionDescription)
        }
    }

    private var conditionsSection: some View {
        Section {
            StringListSection(title: "SSID Match", placeholder: "Add SSID", items: $rule.ssidMatch)
            StringListSection(title: "DNS Search Domain", placeholder: "Add domain", items: $rule.dnsSearchDomainMatch)
            StringListSection(title: "DNS Server Address", placeholder: "Add DNS server IP", items: $rule.dnsServerAddressMatch)
            probeURLSection
        } header: {
            Text("Conditions")
        } footer: {
            Text("All specified conditions must match for the rule to apply. Leave empty to match any network.")
        }
    }

    @ViewBuilder
    private var probeURLSection: some View {
        #if !os(tvOS)
            VStack(alignment: .leading) {
                HStack {
                    Text("Probe URL")
                    Spacer()
                    TextField("http://...", text: $rule.probeURL)
                        .multilineTextAlignment(.trailing)
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
                }
                if !isProbeURLValid {
                    Text("Only HTTP and HTTPS URLs are allowed")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        #else
            HStack {
                Text("Probe URL")
                Spacer()
                Text(rule.probeURL.isEmpty ? "Not set" : rule.probeURL)
                    .foregroundStyle(.secondary)
            }
        #endif
    }

    private var connectionRulesSection: some View {
        Section {
            if rule.connectionRules.isEmpty {
                Text("No connection rules. Add rules to specify which domains trigger VPN connection.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(rule.connectionRules) { connRule in
                    Button {
                        editingConnectionRule = connRule
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(connRule.action.name)
                                    .fontWeight(.medium)
                                if !connRule.matchDomains.isEmpty {
                                    Text(connRule.matchDomains.prefix(3).joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            #if !os(tvOS)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            #endif
                        }
                        .contentShape(Rectangle())
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #elseif os(iOS)
                    .foregroundStyle(.primary)
                    #endif
                }
                .onMove { from, to in
                    rule.connectionRules.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    rule.connectionRules.remove(atOffsets: offsets)
                }
            }
        } header: {
            HStack {
                Text("Connection Rules")
                Spacer()
                Button {
                    isAddingConnectionRule = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                #if os(macOS)
                .buttonStyle(.plain)
                #endif
            }
        } footer: {
            Text("When action is 'Evaluate Connection', these rules determine whether to connect based on the destination host.")
        }
    }
}

private struct EvaluateConnectionRuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: EvaluateConnectionRule
    private let onSave: (EvaluateConnectionRule) -> Void

    @State private var domainText = ""
    @State private var dnsServerText = ""
    @State private var dnsServerError: String?

    private func isValidIPAddress(_ string: String) -> Bool {
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        return string.withCString { cstring in
            inet_pton(AF_INET, cstring, &sin.sin_addr) == 1 ||
                inet_pton(AF_INET6, cstring, &sin6.sin6_addr) == 1
        }
    }

    private var isProbeURLValid: Bool {
        guard !rule.probeURL.isEmpty else { return true }
        guard let url = URL(string: rule.probeURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return true
    }

    private var canSave: Bool {
        !rule.matchDomains.isEmpty && isProbeURLValid
    }

    init(rule: EvaluateConnectionRule, onSave: @escaping (EvaluateConnectionRule) -> Void) {
        _rule = State(initialValue: rule)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                Picker("Action", selection: $rule.action) {
                    ForEach(EvaluateConnectionRuleAction.allCases) { action in
                        Text(action.name).tag(action)
                    }
                }
                #if os(iOS)
                .pickerStyle(.menu)
                #endif
            } header: {
                Text("Action")
            } footer: {
                if rule.action == .connectIfNeeded {
                    Text("Connect VPN if the destination is not directly accessible.")
                } else {
                    Text("Never connect VPN for matching domains.")
                }
            }

            Section {
                matchDomainsSection
            } header: {
                Text("Match Domains")
            } footer: {
                Text("Domains that trigger this rule. The rule matches if the destination host shares a suffix with any domain in this list.")
            }

            if rule.action == .connectIfNeeded {
                Section {
                    useDNSServersSection
                } header: {
                    Text("DNS Servers")
                } footer: {
                    Text("DNS servers to use for resolving the destination. If resolution fails, VPN is started.")
                }

                #if !os(tvOS)
                    Section {
                        HStack {
                            Text("Probe URL")
                            Spacer()
                            TextField("http://...", text: $rule.probeURL)
                                .multilineTextAlignment(.trailing)
                            #if os(iOS)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                            #endif
                        }
                    } header: {
                        Text("Probe URL")
                    } footer: {
                        Text("If set, a request is sent to this URL. If it doesn't return HTTP 200, VPN is started.")
                    }
                #endif
            }
        }
        .navigationTitle("Connection Rule")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        #if os(macOS)
            .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private var matchDomainsSection: some View {
        #if !os(tvOS)
            ForEach(rule.matchDomains, id: \.self) { domain in
                HStack {
                    Text(domain)
                    Spacer()
                    Button {
                        rule.matchDomains.removeAll { $0 == domain }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Add domain (e.g., example.com)", text: $domainText)
                    .onSubmit {
                        addDomain()
                    }
                Button {
                    addDomain()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(domainText.isEmpty)
            }
        #else
            ForEach(rule.matchDomains, id: \.self) { domain in
                Text(domain)
            }
            .onDelete { offsets in
                rule.matchDomains.remove(atOffsets: offsets)
            }
        #endif
    }

    @ViewBuilder
    private var useDNSServersSection: some View {
        #if !os(tvOS)
            ForEach(rule.useDNSServers, id: \.self) { server in
                HStack {
                    Text(server)
                    Spacer()
                    Button {
                        rule.useDNSServers.removeAll { $0 == server }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading) {
                HStack {
                    TextField("Add DNS server IP", text: $dnsServerText)
                        .onSubmit {
                            addDNSServer()
                        }
                    Button {
                        addDNSServer()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(dnsServerText.isEmpty)
                }
                if let error = dnsServerError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        #else
            ForEach(rule.useDNSServers, id: \.self) { server in
                Text(server)
            }
            .onDelete { offsets in
                rule.useDNSServers.remove(atOffsets: offsets)
            }
        #endif
    }

    private func addDomain() {
        let trimmed = domainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !rule.matchDomains.contains(trimmed) {
            rule.matchDomains.append(trimmed)
        }
        domainText = ""
    }

    private func addDNSServer() {
        let trimmed = dnsServerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dnsServerText = ""
            return
        }
        guard isValidIPAddress(trimmed) else {
            dnsServerError = "Invalid IP address"
            return
        }
        dnsServerError = nil
        if !rule.useDNSServers.contains(trimmed) {
            rule.useDNSServers.append(trimmed)
        }
        dnsServerText = ""
    }
}

private struct StringListSection: View {
    let title: String
    let placeholder: String
    @Binding var items: [String]
    @State private var inputText = ""

    var body: some View {
        #if !os(tvOS)
            DisclosureGroup {
                ForEach(items, id: \.self) { item in
                    HStack {
                        Text(item)
                        Spacer()
                        Button {
                            items.removeAll { $0 == item }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField(placeholder, text: $inputText)
                        .onSubmit {
                            addItem()
                        }
                    Button {
                        addItem()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        #else
            NavigationLink {
                StringListEditView(title: title, placeholder: placeholder, items: $items)
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        #endif
    }

    private func addItem() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !items.contains(trimmed) {
            items.append(trimmed)
        }
        inputText = ""
    }
}

#if os(tvOS)
    private struct StringListEditView: View {
        let title: String
        let placeholder: String
        @Binding var items: [String]
        @State private var inputText = ""

        var body: some View {
            List {
                Section {
                    ForEach(items, id: \.self) { item in
                        Text(item)
                    }
                    .onDelete { offsets in
                        items.remove(atOffsets: offsets)
                    }
                }
                Section {
                    HStack {
                        TextField(placeholder, text: $inputText)
                        Button("Add") {
                            addItem()
                        }
                        .disabled(inputText.isEmpty)
                    }
                }
            }
            .navigationTitle(title)
        }

        private func addItem() {
            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !items.contains(trimmed) {
                items.append(trimmed)
            }
            inputText = ""
        }
    }
#endif
