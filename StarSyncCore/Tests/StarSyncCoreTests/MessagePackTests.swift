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
}
