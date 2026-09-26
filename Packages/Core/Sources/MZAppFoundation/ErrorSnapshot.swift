import Foundation

/// A location in source code, never an absolute build-machine path.
public struct LogSource: Equatable, Sendable {
    public let file: String
    public let function: String
    public let line: UInt
    public init(file: String = #fileID, function: String = #function, line: UInt = #line) {
        self.file = file.hasPrefix("/") ? String(file.split(separator: "/").suffix(2).joined(separator: "/")) : file
        self.function = function
        self.line = line
    }
}

/// Opt in only for app-authored technical explanations that contain no user data.
/// Arbitrary localizedDescription/userInfo are deliberately not serialized.
public protocol LoggableError: Error {
    var logMessage: String { get }
}

/// Errors may retain a previously captured stack with truthful provenance.
public protocol ErrorStackProviding: Error {
    var logStack: ErrorStack { get }
}

public struct ErrorStack: Equatable, Sendable {
    public enum Origin: String, Sendable { case reporting, supplied }
    public let origin: Origin
    /// Innermost first. Symbols are for local inspection; addresses support SDK adapters.
    public let symbols: [String]
    public let addresses: [UInt64]
    public init(origin: Origin, symbols: [String], addresses: [UInt64] = []) {
        self.origin = origin
        self.symbols = symbols.prefix(64).map { String($0.prefix(1024)) }
        self.addresses = Array(addresses.prefix(64))
    }
    public static func reporting() -> Self {
        // Capture synchronously before hopping to a logger actor or enqueueing delivery.
        let addresses = Thread.callStackReturnAddresses.map(\.uint64Value)
        let symbols = Thread.callStackSymbols
        return Self(origin: .reporting, symbols: symbols, addresses: addresses)
    }
}

/// App-owned wrappers can preserve captured evidence while changing presentation errors.
public protocol UnderlyingErrorSnapshotProviding: Error {
    var underlyingLogError: ErrorSnapshot? { get }
}

/// Immutable vendor-independent error evidence. No raw Error crosses delivery queues.
public struct ErrorSnapshot: Equatable, Sendable {
    public struct Cause: Equatable, Sendable {
        public let type: String
        public let domain: String
        public let code: Int
        public let message: String?
    }
    /// Outer error first; limited to eight causes and protected against NSError cycles.
    public let causes: [Cause]
    public let stack: ErrorStack
    public let source: LogSource

    public init(_ error: any Error, stack: ErrorStack? = nil,
                file: String = #fileID, function: String = #function, line: UInt = #line) {
        let underlying = (error as? any UnderlyingErrorSnapshotProviding)?.underlyingLogError
        self.source = underlying?.source ?? LogSource(file: file, function: function, line: line)
        self.stack = stack ?? (error as? any ErrorStackProviding)?.logStack ?? underlying?.stack ?? .reporting()
        var causes: [Cause] = []
        var seen: Set<ObjectIdentifier> = []
        var current: (any Error)? = error
        while let value = current, causes.count < 8 {
            let ns = value as NSError
            guard seen.insert(ObjectIdentifier(ns)).inserted else { break }
            causes.append(Cause(type: String(reflecting: Swift.type(of: value)),
                                domain: Self.safeToken(ns.domain), code: ns.code,
                                message: (value as? any LoggableError).map { Self.safeMessage($0.logMessage) }))
            current = ns.userInfo[NSUnderlyingErrorKey] as? any Error
        }
        if let underlying { causes.append(contentsOf: underlying.causes.prefix(max(0, 8 - causes.count))) }
        self.causes = causes
    }

    public static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    private static func safeToken(_ value: String) -> String {
        guard value.range(of: #"^[A-Za-z0-9_.-]{1,200}$"#, options: .regularExpression) != nil else {
            return "redacted"
        }
        return value
    }
    private static func safeMessage(_ value: String) -> String {
        // Defense in depth for opt-in technical messages; this is not a PII classifier.
        var result = String(value.prefix(1024))
        for pattern in [#"(?i)\b(?:https?|file)://\S+"#, #"(?:/Users/|/private/|/var/|/tmp/)\S+"#,
                        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                        #"(?i)(?:token|password|secret|authorization|api[_-]?key)\s*[:=]\s*\S+"#] {
            result = result.replacingOccurrences(of: pattern, with: "<redacted>", options: [.regularExpression, .caseInsensitive])
        }
        return result
    }
}
