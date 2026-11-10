import Foundation

/// A decoded MessagePack value.
///
/// Lightroom CC stores every catalog record as a MessagePack map in the
/// `revs.content` blob column. This is a reader only — StarSync never writes
/// to a Lightroom catalog.
public enum MPValue: Sendable, Equatable {
    case nil_
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case binary(Data)
    case array([MPValue])
    case map([String: MPValue])
}

public struct MessagePackError: Error, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Decoding

public enum MessagePack {
    /// Decodes the first MessagePack value in `data`.
    public static func decode(_ data: Data) throws -> MPValue {
        var reader = Reader(data)
        return try reader.value()
    }

    /// Decodes a top-level map, the shape of every Lightroom catalog record.
    ///
    /// `skippingKeys` is matched against top-level keys only and skips the
    /// value without materializing it. Lightroom embeds multi-kilobyte XMP in
    /// `develop.xmpCameraRaw`; skipping `develop` across 4,000 assets is the
    /// difference between a snappy read and a sluggish one.
    public static func decodeMap(
        _ data: Data,
        skippingKeys skipped: Set<String> = []
    ) throws -> [String: MPValue] {
        var reader = Reader(data)
        return try reader.topLevelMap(skipping: skipped)
    }
}

private struct Reader {
    let bytes: [UInt8]
    var index: Int = 0

    init(_ data: Data) { self.bytes = [UInt8](data) }

    mutating func topLevelMap(skipping skipped: Set<String>) throws -> [String: MPValue] {
        let header = try byte()
        let count: Int
        switch header {
        case 0x80...0x8f: count = Int(header & 0x0f)
        case 0xde: count = Int(try uint16())
        case 0xdf: count = Int(try uint32())
        default:
            throw MessagePackError("expected a map at offset 0, found 0x\(hex(header))")
        }
        var result = [String: MPValue](minimumCapacity: count)
        for _ in 0..<count {
            guard case let .string(key) = try value() else {
                throw MessagePackError("map key was not a string")
            }
            if skipped.contains(key) {
                try skipValue()
            } else {
                result[key] = try value()
            }
        }
        return result
    }

    mutating func value() throws -> MPValue {
        let header = try byte()
        switch header {
        case 0x00...0x7f: return .uint(UInt64(header))                   // positive fixint
        case 0xe0...0xff: return .int(Int64(Int8(bitPattern: header)))   // negative fixint
        case 0x80...0x8f: return .map(try map(count: Int(header & 0x0f)))
        case 0x90...0x9f: return .array(try array(count: Int(header & 0x0f)))
        case 0xa0...0xbf: return .string(try string(count: Int(header & 0x1f)))
        case 0xc0: return .nil_
        case 0xc2: return .bool(false)
        case 0xc3: return .bool(true)
        case 0xc4: return .binary(try binary(count: Int(try byte())))
        case 0xc5: return .binary(try binary(count: Int(try uint16())))
        case 0xc6: return .binary(try binary(count: Int(try uint32())))
        case 0xca: return .double(Double(Float(bitPattern: try uint32())))
        case 0xcb: return .double(Double(bitPattern: try uint64()))
        case 0xcc: return .uint(UInt64(try byte()))
        case 0xcd: return .uint(UInt64(try uint16()))
        case 0xce: return .uint(UInt64(try uint32()))
        case 0xcf: return .uint(try uint64())
        case 0xd0: return .int(Int64(Int8(bitPattern: try byte())))
        case 0xd1: return .int(Int64(Int16(bitPattern: try uint16())))
        case 0xd2: return .int(Int64(Int32(bitPattern: try uint32())))
        case 0xd3: return .int(Int64(bitPattern: try uint64()))
        case 0xd9: return .string(try string(count: Int(try byte())))
        case 0xda: return .string(try string(count: Int(try uint16())))
        case 0xdb: return .string(try string(count: Int(try uint32())))
        case 0xdc: return .array(try array(count: Int(try uint16())))
        case 0xdd: return .array(try array(count: Int(try uint32())))
        case 0xde: return .map(try map(count: Int(try uint16())))
        case 0xdf: return .map(try map(count: Int(try uint32())))
        // Extension types: Lightroom does not use them, but skip them cleanly
        // rather than aborting a whole catalog read.
        case 0xd4: return try ext(fixed: 1)
        case 0xd5: return try ext(fixed: 2)
        case 0xd6: return try ext(fixed: 4)
        case 0xd7: return try ext(fixed: 8)
        case 0xd8: return try ext(fixed: 16)
        case 0xc7: let n = Int(try byte()); return try ext(fixed: n)
        case 0xc8: let n = Int(try uint16()); return try ext(fixed: n)
        case 0xc9: let n = Int(try uint32()); return try ext(fixed: n)
        default:
            throw MessagePackError("unsupported tag 0x\(hex(header)) at offset \(index - 1)")
        }
    }

    /// Advances past one value without building it.
    mutating func skipValue() throws {
        _ = try value()
    }

    // MARK: Containers

    private mutating func map(count: Int) throws -> [String: MPValue] {
        var result = [String: MPValue](minimumCapacity: count)
        for _ in 0..<count {
            let key = try value()
            let v = try value()
            switch key {
            case .string(let s): result[s] = v
            case .uint(let u): result[String(u)] = v
            case .int(let i): result[String(i)] = v
            default: throw MessagePackError("unsupported map key \(key)")
            }
        }
        return result
    }

    private mutating func array(count: Int) throws -> [MPValue] {
        var result = [MPValue]()
        result.reserveCapacity(count)
        for _ in 0..<count { result.append(try value()) }
        return result
    }

    private mutating func ext(fixed length: Int) throws -> MPValue {
        _ = try byte() // type byte
        return .binary(try binary(count: length))
    }

    // MARK: Primitives

    private mutating func byte() throws -> UInt8 {
        guard index < bytes.count else { throw MessagePackError("unexpected end of data") }
        defer { index += 1 }
        return bytes[index]
    }

    private mutating func uint16() throws -> UInt16 {
        let hi = try byte(), lo = try byte()
        return UInt16(hi) << 8 | UInt16(lo)
    }

    private mutating func uint32() throws -> UInt32 {
        var v: UInt32 = 0
        for _ in 0..<4 { v = v << 8 | UInt32(try byte()) }
        return v
    }

    private mutating func uint64() throws -> UInt64 {
        var v: UInt64 = 0
        for _ in 0..<8 { v = v << 8 | UInt64(try byte()) }
        return v
    }

    private mutating func slice(count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, index + count <= bytes.count else {
            throw MessagePackError("length \(count) runs past the end of data")
        }
        defer { index += count }
        return bytes[index..<(index + count)]
    }

    private mutating func string(count: Int) throws -> String {
        let raw = try slice(count: count)
        // Lightroom writes device names with smart quotes and other non-ASCII;
        // decode leniently rather than failing a catalog read over one byte.
        return String(decoding: raw, as: UTF8.self)
    }

    private mutating func binary(count: Int) throws -> Data {
        Data(try slice(count: count))
    }
}

private func hex(_ b: UInt8) -> String {
    String(format: "%02x", b)
}

// MARK: - Convenience accessors

public extension MPValue {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .int(let i): return Int(i)
        case .uint(let u): return Int(u)
        case .double(let d): return Int(d)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var mapValue: [String: MPValue]? {
        if case .map(let m) = self { return m }
        return nil
    }

    var arrayValue: [MPValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    subscript(key: String) -> MPValue? {
        mapValue?[key]
    }
}

public extension Dictionary where Key == String, Value == MPValue {
    /// Follows a dotted path, e.g. `importSource.fileName`.
    func path(_ path: String) -> MPValue? {
        var current: MPValue? = .map(self)
        for component in path.split(separator: ".") {
            current = current?[String(component)]
            if current == nil { return nil }
        }
        return current
    }

    func string(_ path: String) -> String? { self.path(path)?.stringValue }
    func int(_ path: String) -> Int? { self.path(path)?.intValue }
}
