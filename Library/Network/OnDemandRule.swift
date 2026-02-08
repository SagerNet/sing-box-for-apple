import Foundation
import NetworkExtension

public enum OnDemandRuleAction: Int, Codable, CaseIterable, Identifiable {
    case connect = 1
    case disconnect = 2
    case evaluateConnection = 3
    case ignore = 4

    public var id: Int {
        rawValue
    }

    public var name: String {
        switch self {
        case .connect:
            return NSLocalizedString("Connect", comment: "")
        case .disconnect:
            return NSLocalizedString("Disconnect", comment: "")
        case .evaluateConnection:
            return NSLocalizedString("Evaluate Connection", comment: "")
        case .ignore:
            return NSLocalizedString("Ignore", comment: "")
        }
    }

    public var actionDescription: String {
        switch self {
        case .connect:
            return NSLocalizedString("Start the VPN connection when conditions match.", comment: "")
        case .disconnect:
            return NSLocalizedString("Stop the VPN connection when conditions match.", comment: "")
        case .evaluateConnection:
            return NSLocalizedString("Evaluate the destination host before deciding to connect.", comment: "")
        case .ignore:
            return NSLocalizedString("Leave the VPN connection in its current state.", comment: "")
        }
    }
}

public enum OnDemandRuleInterfaceType: Int, Codable, Identifiable {
    case any = 0
    #if os(macOS) || os(tvOS)
        case ethernet = 1
    #endif
    case wifi = 2
    #if os(iOS)
        case cellular = 3
    #endif

    public var id: Int {
        rawValue
    }

    public var name: String {
        switch self {
        case .any:
            return NSLocalizedString("Any", comment: "")
        #if os(macOS) || os(tvOS)
            case .ethernet:
                return NSLocalizedString("Ethernet", comment: "")
        #endif
        case .wifi:
            return NSLocalizedString("Wi-Fi", comment: "")
        #if os(iOS)
            case .cellular:
                return NSLocalizedString("Cellular", comment: "")
        #endif
        }
    }

    public static var availableCases: [OnDemandRuleInterfaceType] {
        #if os(iOS)
            return [.any, .wifi, .cellular]
        #elseif os(macOS)
            return [.any, .ethernet, .wifi]
        #elseif os(tvOS)
            return [.any, .ethernet, .wifi]
        #endif
    }
}

public enum EvaluateConnectionRuleAction: Int, Codable, CaseIterable, Identifiable {
    case connectIfNeeded = 1
    case neverConnect = 2

    public var id: Int {
        rawValue
    }

    public var name: String {
        switch self {
        case .connectIfNeeded:
            return NSLocalizedString("Connect If Needed", comment: "")
        case .neverConnect:
            return NSLocalizedString("Never Connect", comment: "")
        }
    }
}

public struct EvaluateConnectionRule: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var action: EvaluateConnectionRuleAction = .connectIfNeeded
    public var matchDomains: [String] = []
    public var useDNSServers: [String] = []
    public var probeURL: String = ""

    private enum CodingKeys: String, CodingKey {
        case id
        case action
        case matchDomains
        case useDNSServers
        case probeURL
    }

    public init() {}

    public init(action: EvaluateConnectionRuleAction, matchDomains: [String], useDNSServers: [String] = [], probeURL: String = "") {
        self.action = action
        self.matchDomains = matchDomains
        self.useDNSServers = useDNSServers
        self.probeURL = probeURL
    }

    func toNERule() -> NEEvaluateConnectionRule {
        let neAction: NEEvaluateConnectionRuleAction
        switch action {
        case .connectIfNeeded:
            neAction = .connectIfNeeded
        case .neverConnect:
            neAction = .neverConnect
        }
        let rule = NEEvaluateConnectionRule(matchDomains: matchDomains, andAction: neAction)
        if !useDNSServers.isEmpty {
            rule.useDNSServers = useDNSServers
        }
        if !probeURL.isEmpty, let url = URL(string: probeURL) {
            rule.probeURL = url
        }
        return rule
    }
}

public struct OnDemandRule: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var action: OnDemandRuleAction = .connect
    public var interfaceType: OnDemandRuleInterfaceType = .any
    public var ssidMatch: [String] = []
    public var dnsSearchDomainMatch: [String] = []
    public var dnsServerAddressMatch: [String] = []
    public var probeURL: String = ""
    public var connectionRules: [EvaluateConnectionRule] = []

    private enum CodingKeys: String, CodingKey {
        case id
        case action
        case interfaceType
        case ssidMatch
        case dnsSearchDomainMatch
        case dnsServerAddressMatch
        case probeURL
        case connectionRules
    }

    public init() {}

    public init(
        action: OnDemandRuleAction,
        interfaceType: OnDemandRuleInterfaceType = .any,
        ssidMatch: [String] = [],
        dnsSearchDomainMatch: [String] = [],
        dnsServerAddressMatch: [String] = [],
        probeURL: String = "",
        connectionRules: [EvaluateConnectionRule] = []
    ) {
        self.action = action
        self.interfaceType = interfaceType
        self.ssidMatch = ssidMatch
        self.dnsSearchDomainMatch = dnsSearchDomainMatch
        self.dnsServerAddressMatch = dnsServerAddressMatch
        self.probeURL = probeURL
        self.connectionRules = connectionRules
    }

    func toNERule() -> NEOnDemandRule {
        let rule: NEOnDemandRule
        switch action {
        case .connect:
            rule = NEOnDemandRuleConnect()
        case .disconnect:
            rule = NEOnDemandRuleDisconnect()
        case .ignore:
            rule = NEOnDemandRuleIgnore()
        case .evaluateConnection:
            let evalRule = NEOnDemandRuleEvaluateConnection()
            let validRules = connectionRules.filter { !$0.matchDomains.isEmpty }
            if !validRules.isEmpty {
                evalRule.connectionRules = validRules.map { $0.toNERule() }
            }
            rule = evalRule
        }

        switch interfaceType {
        case .any:
            rule.interfaceTypeMatch = .any
        #if os(macOS) || os(tvOS)
            case .ethernet:
                rule.interfaceTypeMatch = .ethernet
        #endif
        case .wifi:
            rule.interfaceTypeMatch = .wiFi
        #if os(iOS)
            case .cellular:
                rule.interfaceTypeMatch = .cellular
        #endif
        }

        if !ssidMatch.isEmpty {
            rule.ssidMatch = ssidMatch
        }

        if !dnsSearchDomainMatch.isEmpty {
            rule.dnsSearchDomainMatch = dnsSearchDomainMatch
        }

        if !dnsServerAddressMatch.isEmpty {
            rule.dnsServerAddressMatch = dnsServerAddressMatch
        }

        if !probeURL.isEmpty, let url = URL(string: probeURL) {
            rule.probeURL = url
        }

        return rule
    }
}
