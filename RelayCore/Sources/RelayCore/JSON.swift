import Foundation

/// A loose JSON value. The gateway's objects carry many optional fields; this keeps parsing tolerant.
public enum JSON: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d):
            if d.rounded() == d, abs(d) < 1e15 { try c.encode(Int64(d)) } else { try c.encode(d) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // MARK: access
    public subscript(_ key: String) -> JSON { if case .object(let o) = self { return o[key] ?? .null }; return .null }
    public subscript(_ i: Int) -> JSON { if case .array(let a) = self, a.indices.contains(i) { return a[i] }; return .null }

    public var isNull: Bool { if case .null = self { return true }; return false }
    public var string: String? {
        switch self { case .string(let s): return s; case .number(let d): return d.rounded() == d ? String(Int64(d)) : String(d); default: return nil }
    }
    public var double: Double? {
        switch self { case .number(let d): return d; case .string(let s): return Double(s); default: return nil }
    }
    public var int: Int? { double.map { Int($0) } }
    public var bool: Bool? {
        switch self { case .bool(let b): return b; case .number(let d): return d != 0; default: return nil }
    }
    public var array: [JSON] { if case .array(let a) = self { return a }; return [] }
    public var object: [String: JSON]? { if case .object(let o) = self { return o }; return nil }

    public func str(_ key: String, _ def: String = "") -> String { self[key].string ?? def }
    public func num(_ key: String, _ def: Double = 0) -> Double { self[key].double ?? def }
    public func flag(_ key: String, _ def: Bool = false) -> Bool { self[key].bool ?? def }
    public func has(_ key: String) -> Bool { !self[key].isNull }

    // MARK: building
    public static func obj(_ pairs: [String: JSON?]) -> JSON { .object(pairs.compactMapValues { $0 }) }

    public func serialized() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        guard let d = try? enc.encode(self), let s = String(data: d, encoding: .utf8) else { return "null" }
        return s
    }

    public static func parse(_ text: String) -> JSON? { parse(Data(text.utf8)) }
    public static func parse(_ data: Data) -> JSON? { try? JSONDecoder().decode(JSON.self, from: data) }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
                ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .number(Double(v)) }
    public init(floatLiteral v: Double) { self = .number(v) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(arrayLiteral e: JSON...) { self = .array(e) }
    public init(dictionaryLiteral e: (String, JSON)...) { self = .object(Dictionary(e, uniquingKeysWith: { $1 })) }
    public init(nilLiteral: ()) { self = .null }
}

public extension JSON {
    init(_ s: String) { self = .string(s) }
    init(_ i: Int) { self = .number(Double(i)) }
    init(_ d: Double) { self = .number(d) }
    init(_ b: Bool) { self = .bool(b) }
    init(_ a: [String]) { self = .array(a.map { .string($0) }) }
}
