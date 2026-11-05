import Foundation
import Testing

@testable import AemiHTML

/// The decoders against Python's codecs on valid text (generated vectors), and against the Encoding Standard's own rules for what is not valid, written out by hand.
@Suite("Decoders")
struct DecoderTests {
    private static func bytes(fromHex hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            result.append(UInt8(hex[index ..< next], radix: 16) ?? 0)
            index = next
        }
        return result
    }

    private static func encoding(named name: String) -> HTMLEncoding {
        HTMLEncoding.allCases.first { String(describing: $0) == name } ?? .utf8
    }

    private func text(_ bytes: [UInt8], _ encoding: HTMLEncoding) -> String {
        String(decoding: HTMLDecoder.decode(bytes[...], as: encoding), as: UTF8.self)
    }

    /// (encoding, bytes, expected UTF-8) as hex, from `decoder-vectors.txt`.
    private static var vectors: [(String, String, String)] {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("decoder-vectors.txt").path
        return ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: " ").map(String.init)
                return line.hasPrefix("#") || parts.count != 3 ? nil : (parts[0], parts[1], parts[2])
            }
    }

    @Test func `valid text decodes as Python decodes it`() {
        var disagreements: [String] = []
        let vectors = Self.vectors
        #expect(vectors.count > 600, "the vectors file is missing or short: \(vectors.count)")
        for (name, hex, expectedHex) in vectors {
            let encoding = Self.encoding(named: name)
            let found = HTMLDecoder.decode(Self.bytes(fromHex: hex)[...], as: encoding)
            if found != Self.bytes(fromHex: expectedHex) { disagreements.append("\(name) \(hex)") }
        }
        // Python's tables differ from the standard's at a few points (EUC-JP's wave dash, GBK's and Big5's extensions); the vectors are the ones both decode alike, and this is the count that does not.
        #expect(
            disagreements.isEmpty,
            "\(disagreements.count) of \(vectors.count): \(disagreements.prefix(3))"
        )
    }

    @Test func `Shift_JIS reads a lead byte and a trail byte, and puts back an ASCII byte that breaks a pair`() {
        #expect(text([0x82, 0xA0], .shiftJIS) == "あ")
        #expect(text([0xB1], .shiftJIS) == "\u{FF71}")
        #expect(text([0x80], .shiftJIS) == "\u{80}")
        #expect(text([0x81], .shiftJIS) == "\u{FFFD}")
        #expect(text([0x81, 0x20], .shiftJIS) == "\u{FFFD} ")
        #expect(text([0xFD], .shiftJIS) == "\u{FFFD}")
        #expect(text([0xF0, 0x40], .shiftJIS) == "\u{E000}")
    }

    @Test func `EUC-JP reads katakana after 0x8E, JIS X 0212 after 0x8F, and puts back an ASCII byte`() {
        #expect(text([0xA4, 0xA2], .eucJP) == "あ")
        #expect(text([0x8E, 0xB1], .eucJP) == "\u{FF71}")
        #expect(text([0xA4], .eucJP) == "\u{FFFD}")
        #expect(text([0xA4, 0x41], .eucJP) == "\u{FFFD}A")
        #expect(text([0xFF], .eucJP) == "\u{FFFD}")
    }

    @Test func `ISO-2022-JP switches with escape sequences`() {
        #expect(text([0x1B, 0x24, 0x42, 0x24, 0x22, 0x1B, 0x28, 0x42, 0x61], .iso2022JP) == "あa")
        #expect(text([0x1B, 0x28, 0x4A, 0x5C, 0x7E], .iso2022JP) == "¥‾")
        #expect(text([0x1B, 0x28, 0x49, 0x31], .iso2022JP) == "\u{FF71}")
        #expect(text([0x1B, 0x24], .iso2022JP) == "\u{FFFD}$")
        #expect(text([0x0E], .iso2022JP) == "\u{FFFD}")
        #expect(text(Array("plain".utf8), .iso2022JP) == "plain")
    }

    @Test func `gb18030 reads one, two and four bytes`() {
        #expect(text([0xB0, 0xA1], .gb18030) == "啊")
        #expect(text([0x80], .gb18030) == "€")
        #expect(text([0x81, 0x30, 0x81, 0x30], .gb18030) == "\u{80}")
        #expect(text([0x84, 0x31, 0xA4, 0x39], .gb18030) == "\u{FFFF}")
        #expect(text([0x90, 0x30, 0x81, 0x30], .gb18030) == "\u{10000}")
        #expect(text([0x81, 0x30, 0x41], .gb18030) == "\u{FFFD}0A")
        #expect(text([0x81], .gb18030) == "\u{FFFD}")
        #expect(text([0xB0, 0xA1], .gbk) == "啊")
    }

    @Test func `Big5 has four pointers that are a letter and a combining mark`() {
        #expect(text([0xA4, 0x40], .big5) == "一")
        #expect(text([0x88, 0x62], .big5) == "\u{CA}\u{304}")
        #expect(text([0x88, 0x64], .big5) == "\u{CA}\u{30C}")
        #expect(text([0x88, 0xA3], .big5) == "\u{EA}\u{304}")
        #expect(text([0x88, 0xA5], .big5) == "\u{EA}\u{30C}")
        #expect(text([0x81, 0x41], .big5) == "\u{FFFD}A")
    }

    @Test func `EUC-KR reads two bytes`() {
        #expect(text([0xB0, 0xA1], .eucKR) == "가")
        #expect(text([0xB0, 0x20], .eucKR) == "\u{FFFD} ")
        #expect(text([0xFF], .eucKR) == "\u{FFFD}")
    }

    @Test func `UTF-16 pairs surrogates and replaces the lone ones and the odd byte`() {
        #expect(text([0x61, 0x00, 0x3D, 0xD8, 0x00, 0xDE], .utf16LE) == "a\u{1F600}")
        #expect(text([0x00, 0x61], .utf16BE) == "a")
        #expect(text([0x00, 0xD8, 0x61, 0x00], .utf16LE) == "\u{FFFD}a")
        #expect(text([0x00, 0xDC], .utf16LE) == "\u{FFFD}")
        #expect(text([0x61, 0x00, 0x62], .utf16LE) == "a\u{FFFD}")
    }

    @Test func `x-user-defined and replacement, and a byte order mark that decides`() {
        #expect(text([0x41, 0x80, 0xFF], .xUserDefined) == "A\u{F780}\u{F7FF}")
        #expect(text([0x41, 0x42], .replacement) == "\u{FFFD}")
        #expect(text([], .replacement) == "")
        let marked: [UInt8] = [0xFF, 0xFE, 0x61, 0x00]
        #expect(String(decoding: HTMLDecoder.decode(marked, as: .windows1252), as: UTF8.self) == "a")
    }

    @Test func `no input makes a decoder fail or loop`() {
        var generator = SystemRandomNumberGenerator()
        for encoding in HTMLEncoding.allCases {
            for _ in 0 ..< 200 {
                let input = (0 ..< Int.random(in: 0 ... 64, using: &generator))
                    .map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
                let output = HTMLDecoder.decode(input[...], as: encoding)
                #expect(String(validating: output, as: UTF8.self) != nil, "\(encoding.name) \(input)")
            }
        }
    }
}
