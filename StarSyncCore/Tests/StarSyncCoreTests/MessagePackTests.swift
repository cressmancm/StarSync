import Foundation
import Testing
@testable import StarSyncCore

@Suite("MessagePack")
struct MessagePackTests {

    @Test("positive and negative fixint")
    func fixint() throws {
        #expect(try MessagePack.decode(Data([0x00])) == .uint(0))
        #expect(try MessagePack.decode(Data([0x7f])) == .uint(127))
        #expect(try MessagePack.decode(Data([0xff])) == .int(-1))
        #expect(try MessagePack.decode(Data([0xe0])) == .int(-32))
    }

    @Test("unsigned integers at every width")
    func unsigned() throws {
        #expect(try MessagePack.decode(Data([0xcc, 0xff])) == .uint(255))
        #expect(try MessagePack.decode(Data([0xcd, 0x01, 0x00])) == .uint(256))
        #expect(try MessagePack.decode(Data([0xce, 0x00, 0x01, 0x00, 0x00])) == .uint(65536))
        #expect(try MessagePack.decode(Data([0xcf, 0, 0, 0, 0, 0, 0, 0x01, 0x00])) == .uint(256))
    }

    @Test("signed integers at every width")
    func signed() throws {
        #expect(try MessagePack.decode(Data([0xd0, 0x80])) == .int(-128))
        #expect(try MessagePack.decode(Data([0xd1, 0xff, 0x00])) == .int(-256))
        #expect(try MessagePack.decode(Data([0xd2, 0xff, 0xff, 0xff, 0x00])) == .int(-256))
        #expect(try MessagePack.decode(Data([0xd3, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00])) == .int(-256))
    }

    @Test("floats")
    func floats() throws {
        var float32 = Data([0xca])
        float32.append(contentsOf: withUnsafeBytes(of: Float(1.5).bitPattern.bigEndian) { Array($0) })
        #expect(try MessagePack.decode(float32) == .double(1.5))

        var float64 = Data([0xcb])
        float64.append(contentsOf: withUnsafeBytes(of: Double(-2.25).bitPattern.bigEndian) { Array($0) })
        #expect(try MessagePack.decode(float64) == .double(-2.25))
    }

    @Test("nil and booleans")
    func simples() throws {
        #expect(try MessagePack.decode(Data([0xc0])) == .nil_)
        #expect(try MessagePack.decode(Data([0xc2])) == .bool(false))
        #expect(try MessagePack.decode(Data([0xc3])) == .bool(true))
    }

    @Test("strings at every width")
    func strings() throws {
        #expect(try MessagePack.decode(Data([0xa3]) + Data("abc".utf8)) == .string("abc"))
        #expect(try MessagePack.decode(Data([0xd9, 3]) + Data("abc".utf8)) == .string("abc"))
        #expect(try MessagePack.decode(Data([0xda, 0, 3]) + Data("abc".utf8)) == .string("abc"))
        #expect(try MessagePack.decode(Data([0xdb, 0, 0, 0, 3]) + Data("abc".utf8)) == .string("abc"))
    }

    @Test("a 300-byte string needs str16")
    func longString() throws {
        let text = String(repeating: "n", count: 300)
        var data = Data([0xda])
        data.append(contentsOf: [UInt8(300 >> 8), UInt8(300 & 0xff)])
        data.append(Data(text.utf8))
        #expect(try MessagePack.decode(data) == .string(text))
    }

    @Test("binary at every width")
    func binary() throws {
        let payload = Data([1, 2, 3])
        #expect(try MessagePack.decode(Data([0xc4, 3]) + payload) == .binary(payload))
        #expect(try MessagePack.decode(Data([0xc5, 0, 3]) + payload) == .binary(payload))
        #expect(try MessagePack.decode(Data([0xc6, 0, 0, 0, 3]) + payload) == .binary(payload))
    }

    @Test("arrays")
    func arrays() throws {
        #expect(try MessagePack.decode(Data([0x93, 0x01, 0x02, 0x03]))
            == .array([.uint(1), .uint(2), .uint(3)]))
        #expect(try MessagePack.decode(Data([0xdc, 0, 2, 0x01, 0x02]))
            == .array([.uint(1), .uint(2)]))
    }

    @Test("maps, including map16")
    func maps() throws {
        let fixmap = Data([0x81, 0xa1]) + Data("a".utf8) + Data([0x05])
        #expect(try MessagePack.decode(fixmap) == .map(["a": .uint(5)]))

        let map16 = Data([0xde, 0, 1, 0xa1]) + Data("a".utf8) + Data([0x05])
        #expect(try MessagePack.decode(map16) == .map(["a": .uint(5)]))
    }

    @Test("nested containers survive a round trip")
    func nested() throws {
        // { "importSource": { "fileName": "DSCF4087.RAF" } }
        var data = Data([0x81, 0xac])
        data.append(Data("importSource".utf8))
        data.append(Data([0x81, 0xa8]))
        data.append(Data("fileName".utf8))
        data.append(Data([0xac]))
        data.append(Data("DSCF4087.RAF".utf8))

        let decoded = try MessagePack.decodeMap(data)
        #expect(decoded.string("importSource.fileName") == "DSCF4087.RAF")
    }

    @Test("skipped keys are stepped over, not decoded")
    func skipping() throws {
        // { "develop": { "a": 1 }, "captureDate": "x" }
        var data = Data([0x82, 0xa7])
        data.append(Data("develop".utf8))
        data.append(Data([0x81, 0xa1]))
        data.append(Data("a".utf8))
        data.append(Data([0x01, 0xab]))
        data.append(Data("captureDate".utf8))
        data.append(Data([0xa1]))
        data.append(Data("x".utf8))

        let decoded = try MessagePack.decodeMap(data, skippingKeys: ["develop"])
        #expect(decoded["develop"] == nil)
        #expect(decoded.string("captureDate") == "x")
    }

    @Test("a dotted path that goes nowhere returns nil, not a crash")
    func missingPath() throws {
        let decoded = try MessagePack.decodeMap(Data([0x80]))
        #expect(decoded.string("importSource.fileName") == nil)
        #expect(decoded.int("ratings.someone.rating") == nil)
    }

    @Test("truncated data throws instead of reading past the end")
    func truncated() {
        #expect(throws: MessagePackError.self) {
            try MessagePack.decode(Data([0xa5, 0x61]))  // claims 5 bytes, has 1
        }
        #expect(throws: MessagePackError.self) {
            try MessagePack.decode(Data([0xcd, 0x01]))  // uint16 missing a byte
        }
        #expect(throws: MessagePackError.self) {
            try MessagePack.decode(Data())
        }
    }

    @Test("a non-map payload is rejected by decodeMap")
    func notAMap() {
        #expect(throws: MessagePackError.self) {
            try MessagePack.decodeMap(Data([0x05]))
        }
    }

    // MARK: - Hostile input
    //
    // The catalog is chosen by the user and reopened at every launch, so a
    // malformed one must throw. A crash here would recur on every start.

    @Test("nesting far past the limit throws instead of overflowing the stack")
    func deepNesting() {
        let depth = 100_000
        let arrays = Data(repeating: 0x91, count: depth)               // [[[[…
        let arrays16 = Data((0..<depth).flatMap { _ in [0xdc, 0x00, 0x01] as [UInt8] })  // array16 of one
        let maps = Data((0..<depth).flatMap { _ in [0x81, 0xa1, 0x61] as [UInt8] })     // {"a": {"a": …
        let mapKeys = Data(repeating: 0x81, count: depth)              // a map as a map's key, as a map's key…
        let record = Data([0x81, 0xa1, 0x6b]) + arrays                 // {"k": [[[…

        #expect(throws: MessagePackError.self) { try MessagePack.decode(arrays) }
        #expect(throws: MessagePackError.self) { try MessagePack.decode(arrays16) }
        #expect(throws: MessagePackError.self) { try MessagePack.decode(maps) }
        #expect(throws: MessagePackError.self) { try MessagePack.decode(mapKeys) }
        #expect(throws: MessagePackError.self) { try MessagePack.decodeMap(maps) }
        #expect(throws: MessagePackError.self) { try MessagePack.decodeMap(record) }
        #expect(throws: MessagePackError.self) {
            try MessagePack.decodeMap(record, skippingKeys: ["k"])
        }
    }

    @Test("nesting exactly at the limit decodes; one deeper throws")
    func nestingLimit() throws {
        let limit = MessagePack.maxNestingDepth
        func arrays(_ n: Int) -> Data { Data(repeating: 0x91, count: n) + Data([0x00]) }

        var expected = MPValue.uint(0)
        for _ in 0..<limit { expected = .array([expected]) }
        #expect(try MessagePack.decode(arrays(limit)) == expected)
        #expect(throws: MessagePackError.self) { try MessagePack.decode(arrays(limit + 1)) }

        // The top-level map is itself one level.
        let fits = Data([0x81, 0xa1, 0x6b]) + arrays(limit - 1)
        let tooDeep = Data([0x81, 0xa1, 0x6b]) + arrays(limit)
        #expect(try MessagePack.decodeMap(fits).count == 1)
        #expect(try MessagePack.decodeMap(fits, skippingKeys: ["k"]).isEmpty)
        #expect(throws: MessagePackError.self) { try MessagePack.decodeMap(tooDeep) }
        #expect(throws: MessagePackError.self) {
            try MessagePack.decodeMap(tooDeep, skippingKeys: ["k"])
        }
    }

    @Test("a declared count larger than the data throws before allocating")
    func oversizedCounts() {
        let huge: [UInt8] = [0xff, 0xff, 0xff, 0xff]
        let cases: [(String, Data)] = [
            ("array32", Data([0xdd] + huge)),
            ("array16", Data([0xdc, 0xff, 0xff, 0x00])),
            ("map32", Data([0xdf] + huge)),
            ("map16", Data([0xde, 0xff, 0xff, 0x00, 0x00])),
            // Three entries need six bytes; five are present.
            ("map16 short by one byte", Data([0xde, 0x00, 0x03, 1, 2, 3, 4, 5])),
            ("str32", Data([0xdb] + huge)),
            ("bin32", Data([0xc6] + huge)),
            ("ext32", Data([0xc9] + huge + [0x01])),
            // Nested, where up-front reservations would multiply.
            ("nested array32", Data(repeating: 0x91, count: 10) + Data([0xdd] + huge)),
        ]
        for (name, data) in cases {
            #expect(throws: MessagePackError.self, "\(name)") { try MessagePack.decode(data) }
            let record = Data([0x81, 0xa1, 0x6b]) + data
            #expect(throws: MessagePackError.self, "\(name) in a record") {
                try MessagePack.decodeMap(record)
            }
            #expect(throws: MessagePackError.self, "\(name) under a skipped key") {
                try MessagePack.decodeMap(record, skippingKeys: ["k"])
            }
        }
        #expect(throws: MessagePackError.self, "top-level map32") {
            try MessagePack.decodeMap(Data([0xdf] + huge))
        }
        #expect(throws: MessagePackError.self, "top-level map16") {
            try MessagePack.decodeMap(Data([0xde, 0x00, 0x02, 0xa1, 0x61, 0x01]))
        }
    }

    @Test("a count that exactly fits the data is not rejected")
    func countBoundary() throws {
        // Two map entries in four bytes, the least they can take.
        #expect(try MessagePack.decode(Data([0x82, 1, 2, 3, 4])) == .map(["1": .uint(2), "3": .uint(4)]))
        #expect(try MessagePack.decode(Data([0x92, 1, 2])) == .array([.uint(1), .uint(2)]))
        #expect(try MessagePack.decode(Data([0xa2, 0x68, 0x69])) == .string("hi"))
    }

    @Test("truncated containers and scalars throw, decoded or skipped")
    func truncatedEverywhere() {
        let cases: [(String, Data)] = [
            ("array missing an element", Data([0x93, 0x01, 0x02])),
            ("map missing a value", Data([0x82, 0xa1, 0x61, 0x01, 0xa1, 0x62])),
            ("float64 short", Data([0xcb, 0, 0, 0])),
            ("float32 short", Data([0xca, 0])),
            ("int64 short", Data([0xd3, 0, 0, 0, 0, 0, 0, 0])),
            ("str8 missing its length", Data([0xd9])),
            ("bin16 short", Data([0xc5, 0x00, 0x04, 1, 2, 3])),
            ("fixext4 missing payload", Data([0xd6, 0x01, 0xaa])),
            ("ext8 missing type byte", Data([0xc7, 0x00])),
        ]
        for (name, data) in cases {
            #expect(throws: MessagePackError.self, "\(name)") { try MessagePack.decode(data) }
            let record = Data([0x81, 0xa1, 0x6b]) + data
            #expect(throws: MessagePackError.self, "\(name) in a record") {
                try MessagePack.decodeMap(record)
            }
            #expect(throws: MessagePackError.self, "\(name) under a skipped key") {
                try MessagePack.decodeMap(record, skippingKeys: ["k"])
            }
        }
        #expect(throws: MessagePackError.self, "record cut off after a key") {
            try MessagePack.decodeMap(Data([0x81, 0xa1, 0x6b]))
        }
    }

    @Test("skipping steps over every type and lands exactly where decoding does")
    func skippingEveryType() throws {
        let full = try MessagePack.decodeMap(Self.richRecord)
        let skipped = try MessagePack.decodeMap(Self.richRecord, skippingKeys: ["develop"])

        #expect(full["develop"]?["xmp"] == .binary(Data([1, 2, 3])))
        #expect(full["develop"]?["arr"]?.arrayValue?.count == 14)
        #expect(full["develop"]?["m"] == .map(["1": .string("a"), "-2": .string("b")]))
        #expect(skipped["develop"] == nil)
        #expect(skipped.string("captureDate") == "x")
        #expect(skipped.int("ratings.u.rating") == 4)
        #expect(skipped == full.filter { $0.key != "develop" })
    }

    @Test("skipping is no more lenient than decoding")
    func skippingRejectsWhatDecodingRejects() {
        let bad: [(String, Data)] = [
            ("unsupported tag", Data([0xc1])),
            ("bool map key", Data([0x81, 0xc3, 0x01])),
            ("array map key", Data([0x81, 0x90, 0x01])),
            ("nil map key", Data([0x81, 0xc0, 0x01])),
        ]
        for (name, value) in bad {
            let record = Data([0x81, 0xa1, 0x6b]) + value
            #expect(throws: MessagePackError.self, "\(name)") { try MessagePack.decodeMap(record) }
            #expect(throws: MessagePackError.self, "\(name), skipped") {
                try MessagePack.decodeMap(record, skippingKeys: ["k"])
            }
        }
    }

    @Test("intValue returns nil for numbers an Int cannot hold, instead of trapping")
    func intValueOutOfRange() {
        #expect(MPValue.uint(.max).intValue == nil)
        #expect(MPValue.uint(UInt64(Int.max) + 1).intValue == nil)
        #expect(MPValue.double(.nan).intValue == nil)
        #expect(MPValue.double(.signalingNaN).intValue == nil)
        #expect(MPValue.double(.infinity).intValue == nil)
        #expect(MPValue.double(-.infinity).intValue == nil)
        #expect(MPValue.double(1e300).intValue == nil)
        #expect(MPValue.double(-1e300).intValue == nil)
        #expect(MPValue.double(0x1p63).intValue == nil)       // one past Int.max

        // Everything that fits behaves as before.
        #expect(MPValue.uint(UInt64(Int.max)).intValue == Int.max)
        #expect(MPValue.int(.min).intValue == Int.min)
        #expect(MPValue.double(-0x1p63).intValue == Int.min)  // exactly Int.min
        #expect(MPValue.double(4.0).intValue == 4)
        #expect(MPValue.double(4.7).intValue == 4)
        #expect(MPValue.double(-4.7).intValue == -4)
        #expect(MPValue.string("4").intValue == nil)
    }

    @Test("random and mutated bytes return or throw, never crash")
    func fuzz() {
        var rng = SplitMix64(seed: 0x5354_4152_5359_4e43)  // "STARSYNC"
        let seeds = [Self.richRecord, Data([0x81, 0xa1, 0x6b, 0x93, 0x01, 0x02, 0x03])]
        // Headers that declare lengths, counts or nesting: where bugs live.
        let interesting: [UInt8] = [
            0x00, 0x7f, 0x80, 0x8f, 0x90, 0x91, 0x9f, 0xa0, 0xbf, 0xc0, 0xc1, 0xc4, 0xc5, 0xc6,
            0xc7, 0xc8, 0xc9, 0xca, 0xcb, 0xcf, 0xd3, 0xd4, 0xd8, 0xd9, 0xda, 0xdb, 0xdc, 0xdd,
            0xde, 0xdf, 0xe0, 0xff,
        ]
        func randomByte() -> UInt8 {
            Bool.random(using: &rng) ? interesting.randomElement(using: &rng)! : .random(in: 0...255, using: &rng)
        }

        var inputs: [Data] = []
        for _ in 0..<3_000 {
            let length = Int.random(in: 0...48, using: &rng)
            inputs.append(Data((0..<length).map { _ in randomByte() }))
        }
        for _ in 0..<3_000 {
            var bytes = [UInt8](seeds.randomElement(using: &rng)!)
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                let at = Int.random(in: 0..<bytes.count, using: &rng)
                switch Int.random(in: 0..<5, using: &rng) {
                case 0: bytes[at] = randomByte()
                case 1: bytes[at] ^= 1 << UInt8.random(in: 0...7, using: &rng)
                case 2: bytes.insert(randomByte(), at: at)
                case 3: if bytes.count > 1 { bytes.remove(at: at) }
                default: bytes.removeSubrange(at...)
                }
                if bytes.isEmpty { bytes = [randomByte()] }
            }
            inputs.append(Data(bytes))
        }

        let skippable: Set<String> = ["develop", "k", "ratings"]
        for data in inputs {
            if let value = try? MessagePack.decode(data) { touchEveryInt(value) }
            let full = try? MessagePack.decodeMap(data)
            let skipped = try? MessagePack.decodeMap(data, skippingKeys: skippable)
            // Skipping must accept and reject exactly what decoding does.
            #expect((full == nil) == (skipped == nil), "\(Array(data))")
            if let full, let skipped {
                #expect(Set(full.keys).subtracting(skippable) == Set(skipped.keys), "\(Array(data))")
                full.values.forEach(touchEveryInt)
            }
        }
    }

    // MARK: - Helpers

    /// Walks a decoded value calling `intValue` on every node, the way the
    /// catalog reader does on ratings and dimensions.
    private func touchEveryInt(_ value: MPValue) {
        _ = value.intValue
        switch value {
        case .array(let a): a.forEach(touchEveryInt)
        case .map(let m): m.values.forEach(touchEveryInt)
        default: break
        }
    }

    /// A record whose `develop` value uses every tag family, so skipping it
    /// proves `skipValue` consumes exactly as many bytes as `value()` would.
    ///
    ///     { "develop": { "xmp": bin, "arr": [ …every scalar… ], "m": {1: "a", -2: "b"} },
    ///       "captureDate": "x", "ratings": { "u": { "rating": 4 } } }
    static let richRecord: Data = {
        func str(_ s: String) -> [UInt8] { [0xa0 | UInt8(s.utf8.count)] + Array(s.utf8) }
        var b: [UInt8] = [0x83]
        b += str("develop") + [0x83]
        b += str("xmp") + [0xc4, 0x03, 0x01, 0x02, 0x03]
        b += str("arr") + [0xdc, 0x00, 0x0e]
        b += [0x01, 0xff]                                      // fixints
        b += [0xca, 0x3f, 0xc0, 0x00, 0x00]                    // float32 1.5
        b += [0xcb, 0xc0, 0x02, 0, 0, 0, 0, 0, 0]              // float64 -2.25
        b += [0xc0, 0xc3, 0xc2]                                // nil, true, false
        b += [0xcd, 0x01, 0x00]                                // uint16
        b += [0xd2, 0xff, 0xff, 0xff, 0x00]                    // int32
        b += [0xd4, 0x01, 0x07]                                // fixext1
        b += [0xc7, 0x02, 0x05, 0xaa, 0xbb]                    // ext8
        b += [0xd9, 0x02, 0x68, 0x69]                          // str8
        b += [0xdf, 0, 0, 0, 0]                                // empty map32
        b += [0xdd, 0, 0, 0, 1, 0x90]                          // array32 of []
        b += str("m") + [0x82, 0x01] + str("a") + [0xfe] + str("b")
        b += str("captureDate") + str("x")
        b += str("ratings") + [0x81] + str("u") + [0x81] + str("rating") + [0x04]
        return Data(b)
    }()
}

/// SplitMix64: tiny and fully determined by its seed, so a fuzz failure
/// reproduces exactly on every run and every machine.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
