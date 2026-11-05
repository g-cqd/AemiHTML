import Foundation
import Testing

@testable import AemiHTML

/// The prescan and the sniffing algorithm, against html5lib's encoding tests (each is a page and the encoding a browser must find in it) and against the cases the standard describes.
@Suite("Encoding sniffing")
struct EncodingSniffingTests {
    static var directory: String {
        let cache =
            ProcessInfo.processInfo.environment["AEMIHTML_CORPUS"] ?? NSHomeDirectory()
            + "/Library/Caches/AemiHTMLCorpus"
        return cache + "/html5lib-tests/encoding"
    }

    static var files: [String] {
        ["tests1.dat", "tests2.dat", "test-yahoo-jp.dat"]
            .filter { FileManager.default.fileExists(atPath: directory + "/" + $0) }
    }

    /// The cases of a `.dat` file: the bytes of `#data` and the label after `#encoding`.
    static func cases(in file: String) -> [(data: [UInt8], expected: String)] {
        guard let all = FileManager.default.contents(atPath: directory + "/" + file) else { return [] }
        let bytes = Array(all)
        let dataMark = Array("#data\n".utf8)
        let encodingMark = Array("\n#encoding\n".utf8)
        func find(_ mark: [UInt8], from: Int) -> Int? {
            guard bytes.count >= mark.count, from <= bytes.count - mark.count else { return nil }
            for index in from ... bytes.count - mark.count where bytes[index ..< index + mark.count].elementsEqual(mark)
            { return index }
            return nil
        }
        var found: [(data: [UInt8], expected: String)] = []
        var position = 0
        while let start = find(dataMark, from: position) {
            let dataStart = start + dataMark.count
            guard let marker = find(encodingMark, from: dataStart) else { break }
            let labelStart = marker + encodingMark.count
            var labelEnd = labelStart
            while labelEnd < bytes.count, bytes[labelEnd] != 0x0A { labelEnd += 1 }
            found.append(
                (Array(bytes[dataStart ..< marker]), String(decoding: bytes[labelStart ..< labelEnd], as: UTF8.self))
            )
            position = labelEnd
        }
        return found
    }

    @Test(arguments: files)
    func `a page's declaration is found as html5lib expects`(file: String) {
        let cases = Self.cases(in: file)
        #expect(!cases.isEmpty)
        var failures: [String] = []
        for (data, expected) in cases {
            // The whole path, as a browser takes it: sniffing, and the parse starting again when a `meta` past the first 1024 bytes names another encoding. html5lib's default, where nothing is declared, is windows-1252.
            let found = HTMLParser.parse(encoded: data, fallbackIsUTF8: false).encoding
            if found != HTMLEncoding(label: expected) {
                failures.append(
                    "expected \(expected), found \(found.name) in \(String(decoding: data.prefix(120), as: UTF8.self).debugDescription)"
                )
            }
        }
        #expect(
            failures.isEmpty,
            Comment(rawValue: "\(failures.count) of \(cases.count)\n" + failures.prefix(6).joined(separator: "\n"))
        )
    }

    @Test func `labels are the standard's, in any case and with white space around`() {
        #expect(HTMLEncoding(label: " Latin1\n") == .windows1252)
        #expect(HTMLEncoding(label: "UTF8") == .utf8)
        #expect(HTMLEncoding(label: "ISO-8859-1") == .windows1252)
        #expect(HTMLEncoding(label: "iso8859-2") == .iso8859_2)
        #expect(HTMLEncoding(label: "sjis") == .shiftJIS)
        #expect(HTMLEncoding(label: "x-sjis") == .shiftJIS)
        #expect(HTMLEncoding(label: "gb2312") == .gbk)
        #expect(HTMLEncoding(label: "big5-hkscs") == .big5)
        #expect(HTMLEncoding(label: "ks_c_5601-1987") == .eucKR)
        #expect(HTMLEncoding(label: "utf-16") == .utf16LE)
        #expect(HTMLEncoding(label: "x-user-defined") == .xUserDefined)
        #expect(HTMLEncoding(label: "klingon") == nil)
        #expect(HTMLEncoding(label: "") == nil)
        #expect(HTMLEncoding(label: String(repeating: "a", count: 5_000)) == nil)
    }

    @Test func `a byte order mark wins over the transport layer and a meta`() {
        let page = [0xEF, 0xBB, 0xBF] + Array("<meta charset=windows-1251>".utf8)
        let result = HTMLEncodingSniffer.sniff(page, transportLabel: "iso-8859-2")
        #expect(result == .init(encoding: .utf8, confidence: .certain, byteOrderMarkLength: 3))
        #expect(HTMLEncodingSniffer.sniff([0xFF, 0xFE, 0x61, 0]).encoding == .utf16LE)
        #expect(HTMLEncodingSniffer.sniff([0xFE, 0xFF, 0, 0x61]).encoding == .utf16BE)
    }

    @Test func `the transport layer wins over a meta, which wins over the fallback`() {
        let page = Array("<meta charset=windows-1251><p>".utf8)
        #expect(
            HTMLEncodingSniffer.sniff(page, transportLabel: "iso-8859-2")
                == .init(encoding: .iso8859_2, confidence: .certain, byteOrderMarkLength: 0)
        )
        #expect(HTMLEncodingSniffer.sniff(page, transportLabel: "klingon").encoding == .windows1251)
        #expect(HTMLEncodingSniffer.sniff(page).confidence == .tentative)
    }

    @Test func `with no declaration, UTF-8 if the bytes are, else windows-1252`() {
        #expect(HTMLEncodingSniffer.sniff(Array("<p>é日本</p>".utf8)).encoding == .utf8)
        #expect(
            HTMLEncodingSniffer.sniff(Array("<p>caf".utf8) + [0xE9, 0x3C, 0x2F, 0x70, 0x3E]).encoding == .windows1252
        )
        #expect(HTMLEncodingSniffer.sniff([0xE9], fallbackIsUTF8: false).encoding == .windows1252)
        #expect(HTMLEncodingSniffer.sniff(Array("plain ascii".utf8), fallbackIsUTF8: false).encoding == .windows1252)
    }

    @Test func `a declaration after the first 1024 bytes is not seen`() {
        let late = Array(String(repeating: " ", count: 1_030).utf8) + Array("<meta charset=windows-1251>".utf8)
        #expect(HTMLEncodingSniffer.prescan(late) == nil)
        let early = Array(String(repeating: " ", count: 900).utf8) + Array("<meta charset=windows-1251>".utf8)
        #expect(HTMLEncodingSniffer.prescan(early) == .windows1251)
    }

    @Test func `UTF-16 declared in a meta means UTF-8, and x-user-defined means windows-1252`() {
        #expect(HTMLEncodingSniffer.prescan(Array("<meta charset=utf-16>".utf8)) == .utf8)
        #expect(HTMLEncodingSniffer.prescan(Array("<meta charset=x-user-defined>".utf8)) == .windows1252)
    }

    @Test func `a pragma without http-equiv, a comment, and a repeated attribute`() {
        #expect(HTMLEncodingSniffer.prescan(Array("<meta content='text/html; charset=windows-1251'>".utf8)) == nil)
        #expect(
            HTMLEncodingSniffer.prescan(
                Array("<meta http-equiv=content-type content='text/html; charset=windows-1251'>".utf8)
            ) == .windows1251
        )
        #expect(
            HTMLEncodingSniffer.prescan(Array("<!-- <meta charset=windows-1251> --><meta charset=iso-8859-2>".utf8))
                == .iso8859_2
        )
        #expect(
            HTMLEncodingSniffer.prescan(Array("<meta charset=windows-1251 charset=iso-8859-2>".utf8)) == .windows1251
        )
        #expect(
            HTMLEncodingSniffer.prescan(Array("<meta charset=\"klingon\"><meta charset=windows-1250>".utf8))
                == .windows1250
        )
    }

    @Test func `a hostile page costs no more than its first kilobyte`() {
        let hostile = Array(String(repeating: "<meta ", count: 400).utf8)
        #expect(HTMLEncodingSniffer.prescan(hostile) == nil)
        let comments = Array(String(repeating: "<!--", count: 400).utf8)
        #expect(HTMLEncodingSniffer.prescan(comments) == nil)
    }
}

/// Whole pages in other encodings, through the parser and the extractor.
@Suite("Pages in other encodings")
struct EncodedPageTests {
    private func text(_ document: HTMLDocument) -> String {
        var out = ""
        for node in document.descendants(of: document.root) where document.kind(node) == .text {
            out += String(decoding: document.data(node), as: UTF8.self)
        }
        return out
    }

    @Test func `a windows-1251 page declared by its meta`() {
        // "Привет" in windows-1251.
        let page =
            Array("<meta charset=windows-1251><p>".utf8) + [0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2] + Array("</p>".utf8)
        let document = HTMLParser.parse(encoded: page)
        #expect(document.encoding == .windows1251)
        #expect(text(document) == "Привет")
    }

    @Test func `a Shift_JIS page given by the transport layer`() {
        let page = Array("<p>".utf8) + [0x82, 0xB1, 0x82, 0xF1, 0x82, 0xC9, 0x82, 0xBF, 0x82, 0xCD] + Array("</p>".utf8)
        let document = HTMLParser.parse(encoded: page, transportEncoding: "Shift_JIS")
        #expect(document.encoding == .shiftJIS)
        #expect(text(document) == "こんにちは")
    }

    @Test func `the transport layer is certain, and a meta does not change it`() {
        let page = Array("<meta charset=windows-1251><p>".utf8) + [0xE9]
        let document = HTMLParser.parse(encoded: page, transportEncoding: "iso-8859-1")
        #expect(document.encoding == .windows1252)
        #expect(text(document).hasSuffix("é"))
    }

    @Test func `with no declaration, valid UTF-8 is UTF-8 and the rest is windows-1252`() {
        #expect(HTMLParser.parse(encoded: Array("<p>é</p>".utf8)).encoding == .utf8)
        let latin = Array("<p>caf".utf8) + [0xE9] + Array("</p>".utf8)
        let document = HTMLParser.parse(encoded: latin)
        #expect(document.encoding == .windows1252)
        #expect(text(document) == "café")
    }

    @Test func `a meta after the first kilobyte restarts the parse with the encoding it names`() {
        let padding = Array(String(repeating: "<!-- x -->", count: 120).utf8)
        let page = padding + Array("<meta charset=windows-1251><p>".utf8) + [0xCF, 0xF0, 0xE8] + Array("</p>".utf8)
        let document = HTMLParser.parse(encoded: page, fallbackIsUTF8: false)
        #expect(document.encoding == .windows1251)
        #expect(text(document) == "При")
    }

    @Test func `UTF-16 with a byte order mark`() {
        var page: [UInt8] = [0xFF, 0xFE]
        for unit in "<p>é日</p>".utf16 { page += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
        let document = HTMLParser.parse(encoded: page)
        #expect(document.encoding == .utf16LE)
        #expect(text(document) == "é日")
    }

    @Test func `the extractor reads encoded bytes`() {
        let page = Array("<title>t</title><p>".utf8) + [0x82, 0xB1, 0x82, 0xF1] + Array("</p>".utf8)
        let extracted = HTMLExtractor.extract(encoded: page, transportEncoding: "shift_jis")
        #expect(extracted.sections.map(\.content).joined().contains("こん"))
    }

    @Test func `a meta that names an encoding the standard does not know changes nothing`() {
        let page = Array("<meta charset=klingon><p>caf".utf8) + [0xE9]
        let document = HTMLParser.parse(encoded: page)
        #expect(document.encoding == .windows1252)
        #expect(text(document) == "café")
    }
}
