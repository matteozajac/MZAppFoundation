import Foundation

public enum TelemetryValue: Equatable, Codable, Sendable {
    case string(String), integer(Int), double(Double), bool(Bool)

    public var rendered: String {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): String(value)
        }
    }
}

public protocol AnalyticsEvent: Sendable {
    var name: String { get }
    var properties: [String: TelemetryValue] { get }
}

public struct TelemetryEvent: AnalyticsEvent, Equatable, Codable, Sendable {
    public let name: String
    public let properties: [String: TelemetryValue]
    public init(_ name: String, properties: [String: TelemetryValue] = [:]) {
        self.name = name
        self.properties = properties
    }
}

/// Schema allowlisting prevents arbitrary domain data from entering any engine, including Pulse.
public struct TelemetrySchema: Equatable, Sendable {
    public let events: [String: Set<String>]
    public init(events: [String: Set<String>]) { self.events = events }

    public func validate(_ event: any AnalyticsEvent) -> TelemetryEvent? {
        guard Self.validName(event.name), let allowed = events[event.name] else { return nil }
        let properties = event.properties.filter { key, value in
            guard allowed.contains(key), Self.validName(key), !RedactionPolicy.isSensitive(key) else { return false }
            if case .double(let number) = value { return number.isFinite }
            if case .string(let text) = value { return text.count <= 100 }
            return true
        }
        return TelemetryEvent(event.name, properties: properties)
    }

    private static func validName(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z][A-Za-z0-9_]{0,39}$", options: .regularExpression) != nil
    }
}
