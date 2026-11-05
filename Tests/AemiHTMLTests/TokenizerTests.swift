import Testing

@testable import AemiHTML

@Suite("The tokenizer")
struct TokenizerTests {
    private func tokens(_ html: String, _ configure: (inout HTMLTokenizer.Options) -> Void = { _ in }) -> HTMLTokens {
        var options = HTMLTokenizer.Options()
        configure(&options)
        return HTMLTokenizer.tokenize(Array(html.utf8), options: options)
    }

    private func text(_ bytes: ArraySlice<UInt8>) -> String { String(decoding: bytes, as: UTF8.self) }

    @Test func `a start tag has its name lower cased, its attributes in order and its self-closing flag`() {
        let found = Array(tokens("<DIV Class=a id='b' data-x=\"c d\" hidden/>").tokens)
        #expect(found.count == 1 && found[0].kind == .startTag)
        let tag = found[0]
        #expect(text(tag.name) == "div" && tag.isSelfClosing)
        #expect(tag.attributes.map { text($0.name) } == ["class", "id", "data-x", "hidden"])
        #expect(tag.attributes.map { text($0.value) } == ["a", "b", "c d", ""])
    }

    @Test func `text is a range of the source until a reference changes it, and a run is one slot`() {
        let plain = tokens("a plain run of text, and <b>more</b>")
        #expect(plain.scratch.isEmpty)
        let decoded = tokens("a &amp; b &#x41; &notit; c")
        let slots = decoded.tokens.filter { $0.kind == .text }
        #expect(slots.count == 1 && text(slots[0].text) == "a & b A ¬it; c")
    }

    @Test func `the first of a repeated attribute wins and the repeat is an error`() {
        let result = tokens("<a x=1 y=2 x=3>") { $0.collectsErrors = true }
        let tag = Array(result.tokens)[0]
        #expect(tag.attributes.map { text($0.value) } == ["1", "2"])
        #expect(result.errors.map(\.code) == [.duplicateAttribute])
    }

    @Test func `a script ends at its own end tag and nothing in it is markup`() {
        let result = tokens("<script>if (a < b && c) { x = '</div>'; }</script><p>")
        let kinds = result.tokens.map(\.kind)
        #expect(kinds == [.startTag, .text, .endTag, .startTag])
        #expect(text(Array(result.tokens)[1].text) == "if (a < b && c) { x = '</div>'; }")
    }

    @Test func `a title is text with references, and a style is text without`() {
        let result = tokens("<title>a &amp; <b></title><style>&amp; <b></style>")
        // Text comes in several slots; the end tags between the two are what separates them.
        var texts: [String] = [""]
        for token in result.tokens {
            if token.kind == .text {
                texts[texts.count - 1] += text(token.text)
            } else if !texts[texts.count - 1].isEmpty {
                texts.append("")
            }
        }
        #expect(texts.filter { !$0.isEmpty } == ["a & <b>", "&amp; <b>"])
    }

    @Test func `carriage returns become line feeds`() {
        #expect(tokens("a\r\nb\rc").tokens.map { text($0.text) }.joined() == "a\nb\nc")
    }

    @Test func `a tag cut off by the end of the input is dropped`() {
        #expect(tokens("text <div class=").tokens.map(\.kind) == [.text])
    }

    @Test func `processing instructions have a target and data`() {
        let found = Array(tokens("<?php echo 1 ?>x").tokens)
        #expect(
            found[0].kind == .processingInstruction && text(found[0].name) == "php" && text(found[0].data) == "echo 1 "
        )
    }

    @Test func `any bytes give tokens, and a long hostile input takes linear time`() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 300 {
            let bytes: [UInt8] = (0 ..< Int.random(in: 0 ... 400, using: &generator))
                .map { _ in
                    [0x3C, 0x3E, 0x26, 0x2F, 0x21, 0x2D, 0x22, 0x27, 0x3D, 0x00, 0x20, 0x61, 0x5B, 0x5D, 0x3F, 0xFF][
                        Int.random(in: 0 ..< 16, using: &generator)
                    ]
                }
            var options = HTMLTokenizer.Options()
            options.collectsErrors = true
            options.allowsCDATA = Bool.random()
            _ = HTMLTokenizer.tokenize(bytes, options: options)
        }
        for pattern in ["<a ", "<!--", "&#", "<![CDATA[", "</", "<a b='", "<script><!--<script>", "&amp", "<?x "] {
            let big = Array(String(repeating: pattern, count: 200_000).utf8)
            let start = ContinuousClock.now
            _ = HTMLTokenizer.tokenize(big)
            #expect(ContinuousClock.now - start < .seconds(20), "\(pattern)")
        }
    }
}

/// The input is decoded as the standard decodes UTF-8: what the document holds is always well-formed.
@Suite("Ill-formed UTF-8")
struct IllFormedInputTests {
    private func text(_ bytes: [UInt8]) -> [UInt8] {
        let document = HTMLParser.parse(bytes)
        var out: [UInt8] = []
        for node in document.descendants(of: document.root) where document.kind(node) == .text {
            out += document.data(node)
        }
        return out
    }

    @Test func `a stray byte becomes one replacement character`() {
        #expect(
            text(Array("a".utf8) + [0xFF] + Array("b".utf8)) == Array("a".utf8) + [0xEF, 0xBF, 0xBD] + Array("b".utf8)
        )
    }

    @Test func `a truncated sequence is one replacement, per maximal subpart`() {
        // E2 82 is the start of a three-byte sequence; F0 90 80 the start of a four-byte one: each is one U+FFFD.
        #expect(text([0xE2, 0x82, 0x41]) == [0xEF, 0xBF, 0xBD, 0x41])
        #expect(text([0xF0, 0x90, 0x80, 0x41]) == [0xEF, 0xBF, 0xBD, 0x41])
        #expect(text([0xC0, 0xAF]) == [0xEF, 0xBF, 0xBD, 0xEF, 0xBF, 0xBD])
        #expect(text([0xED, 0xA0, 0x80]) == [0xEF, 0xBF, 0xBD, 0xEF, 0xBF, 0xBD, 0xEF, 0xBF, 0xBD])
    }

    @Test func `a byte order mark is dropped and well-formed text is untouched`() {
        #expect(text([0xEF, 0xBB, 0xBF] + Array("é日本🙂".utf8)) == Array("é日本🙂".utf8))
    }

    @Test func `the result is always valid UTF-8`() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 500 {
            let bytes = (0 ..< Int.random(in: 0 ... 200, using: &generator))
                .map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
            let out = text(bytes)
            #expect(String(validating: out, as: UTF8.self) != nil)
        }
    }
}
