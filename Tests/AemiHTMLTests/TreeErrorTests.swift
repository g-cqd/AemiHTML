import Foundation
import Testing

@testable import AemiHTML

/// The parse errors of tree construction, case by case. Each case is a document and the classes of error the standard's rules give it, worked out from the rules (13.2.6.4), not from this builder's output.
@Suite("The tree builder's parse errors")
struct TreeErrorTests {
    private static let doctype = "<!DOCTYPE html>"

    private static func options() -> HTMLParser.Options {
        var options = HTMLParser.Options()
        options.collectsErrors = true
        return options
    }

    private static func errors(_ html: String) -> [HTMLTreeError] {
        HTMLParser.parse(Array(html.utf8), options: options()).treeErrors.map(\.kind)
    }

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let html: String
        let wanted: [HTMLTreeError]
        var testDescription: String { name }
        init(_ name: String, _ html: String, _ wanted: [HTMLTreeError]) {
            self.name = name
            self.html = html
            self.wanted = wanted
        }
    }

    private static let d = doctype

    static let cases: [Case] = [
        // Nothing wrong.
        Case("a conforming document", d + "<html><head><title>t</title></head><body><p>x</p></body></html>", []),
        Case("implied html, head and body", d + "<title>t</title><p>x", []),
        Case("elements the end of the input may leave open", d + "<li>a<li>b", []),
        Case("a table the end of the input leaves open", d + "<table><tr><td>x", [.unexpectedEndOfFile]),
        Case("an option closed by the next option", d + "<select><option>a<option>b</select>", []),
        Case("a custom element", d + "<my-tag>x</my-tag>", []),
        // Doctype.
        Case("no doctype", "<p>x</p>", [.missingDoctype]),
        Case(
            "a doctype with a public identifier",
            "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\"><p>x</p>",
            [.nonConformingDoctype]
        ),
        Case("a doctype that is not html", "<!DOCTYPE foo><p>x</p>", [.nonConformingDoctype]),
        Case("the legacy-compat doctype is conforming", "<!DOCTYPE html SYSTEM \"about:legacy-compat\"><p>x</p>", []),
        Case("a second doctype", d + d + "<p>x</p>", [.unexpectedDoctype]),
        Case("a doctype in the body", d + "<body><!DOCTYPE html>", [.unexpectedDoctype]),
        // Before the body.
        Case("an end tag before html", d + "</span><html><head></head><body></body></html>", [.unexpectedEndTag]),
        Case("an end tag before head", d + "<html></span><head></head><body></body></html>", [.unexpectedEndTag]),
        Case("a second head", d + "<head><head></head><body></body>", [.unexpectedStartTag]),
        Case("a stray end tag in the head", d + "<head></span></head><body></body>", [.unexpectedEndTag]),
        Case("a template end tag with no template", d + "<head></template></head><body></body>", [.unexpectedEndTag]),
        Case(
            "a template closed with an element open",
            d + "<head><template><div></template></head><body></body>",
            [.unclosedElement]
        ),
        Case(
            "a body element in the noscript of the head",
            d + "<head><noscript><p>x</noscript>",
            [.unexpectedStartTag, .unexpectedEndTag]
        ),
        Case("a head after the head", d + "<head></head><head>", [.unexpectedStartTag]),
        Case("a head tag that belongs in the head, after it", d + "<head></head><meta>", [.unexpectedStartTag]),
        Case("a stray end tag after the head", d + "<head></head></span>", [.unexpectedEndTag]),
        // In body: start tags.
        Case("html again", d + "<body><html lang=en>", [.unexpectedStartTag]),
        Case("body again", d + "<body><body>", [.unexpectedStartTag]),
        Case("a frameset in the body", d + "<body><frameset>", [.unexpectedStartTag]),
        Case(
            "a heading in a heading (the first is closed by the second)",
            d + "<h1><h2>x</h2></h1>",
            [.nestedElement, .unexpectedEndTag]
        ),
        Case("a form in a form", d + "<form><form></form></form>", [.nestedElement, .unexpectedEndTag]),
        Case("a button in a button", d + "<button><button></button>", [.nestedElement]),
        Case("an a in an a", d + "<a><a></a>", [.nestedElement]),
        Case("a nobr in a nobr", d + "<nobr><nobr></nobr>", [.nestedElement]),
        Case("a select in a select", d + "<select><select>", [.nestedElement]),
        Case("an input in a select", d + "<select><input>", [.unexpectedStartTag]),
        Case("an hr in a select with an option open", d + "<select><option><hr></select>", []),
        Case(
            "an hr in a select with an option under a b",
            d + "<select><option><b><hr></b></option></select>",
            [.unexpectedStartTag]
        ),
        Case("an image", d + "<image>", [.imageStartTag]),
        Case("an rb outside ruby", d + "<rb>", [.unclosedElement]),
        Case("an rt outside ruby", d + "<rt>", [.unclosedElement]),
        Case("an rt inside ruby", d + "<ruby>a<rt>b</rt></ruby>", []),
        Case("a table part in the body", d + "<body><caption>", [.unexpectedStartTag]),
        Case("a tr in the body", d + "<body><tr>", [.unexpectedStartTag]),
        Case("a NUL in the body", d + "<body>\u{0}", [.unexpectedNullCharacter]),
        // In body: end tags and the end of the input.
        Case("an end tag with no element", d + "<body></div>", [.unexpectedEndTag]),
        Case("a div closed over a span", d + "<div><span></div>", [.unclosedElement]),
        Case("the body closed over a div", d + "<body><div></body>", [.unclosedElement]),
        Case("the end of the input over a div", d + "<div>", [.unexpectedEndOfFile]),
        Case("an end p with no p", d + "<p></p></p>", [.unexpectedEndTag]),
        Case("an end li with no li", d + "<li>x</li></li>", [.unexpectedEndTag]),
        Case("an end heading with no heading", d + "<body></h1>", [.unexpectedEndTag]),
        Case("an h2 end tag over an h1", d + "<h1>x</h2>", [.unclosedElement]),
        Case("a br end tag", d + "<body></br>", [.unexpectedEndTag]),
        Case("a form end tag with no form", d + "<body></form>", [.unexpectedEndTag]),
        Case("misnested formatting", d + "<b><i></b></i>", [.misnestedFormattingElement, .misnestedFormattingElement]),
        Case("a formatting end tag nothing opened", d + "<body></b>", [.unexpectedEndTag]),
        Case("an unclosed script at the end of the input", d + "<script>x", [.unexpectedEndOfFile]),
        // Tables.
        Case("text in a table", d + "<table>x</table>", [.fosterParenting]),
        Case(
            "three characters in a table are three errors",
            d + "<table>xyz</table>",
            [.fosterParenting, .fosterParenting, .fosterParenting]
        ),
        Case(
            "two NULs in the body are two errors",
            d + "<body>\u{0}\u{0}",
            [.unexpectedNullCharacter, .unexpectedNullCharacter]
        ),
        Case("text handed on from after the body is one error", d + "<body></body>xy", [.unexpectedCharacter]),
        Case(
            "text ignored after the frameset is an error each",
            d + "<frameset></frameset>xy",
            [.unexpectedCharacter, .unexpectedCharacter]
        ),
        Case("a character of two bytes is one error", d + "<table>\u{E9}</table>", [.fosterParenting]),
        Case("an element in a table", d + "<table><div></div></table>", [.fosterParenting, .fosterParenting]),
        Case("a table in a table", d + "<table><table></table>", [.nestedElement]),
        Case("a hidden input in a table", d + "<table><input type=hidden></table>", [.unexpectedStartTag]),
        Case("an input that is not hidden in a table", d + "<table><input></table>", [.fosterParenting]),
        Case(
            "a form in a table",
            d + "<table><form></form></table>",
            [.unexpectedStartTag, .fosterParenting, .unexpectedEndTag]
        ),
        Case("an end div in a table", d + "<table></div></table>", [.fosterParenting, .unexpectedEndTag]),
        Case("an end body in a table", d + "<table></body></table>", [.unexpectedEndTag]),
        Case("an end tr in a table", d + "<table></tr></table>", [.unexpectedEndTag]),
        Case("an end td in a table body", d + "<table><tbody></td></tbody></table>", [.unexpectedEndTag]),
        Case("a td straight in a table body", d + "<table><tbody><td>x</table>", [.unexpectedStartTag]),
        Case("a second end caption", d + "<table><caption></caption></caption></table>", [.unexpectedEndTag]),
        Case("an end col in a column group", d + "<table><colgroup></col></colgroup></table>", [.unexpectedEndTag]),
        Case("an end body in a cell", d + "<table><tr><td></body></td></tr></table>", [.unexpectedEndTag]),
        Case("a cell closed over a b", d + "<table><tr><td><b></td></tr></table>", [.unclosedElement]),
        Case("a caption closed over a b", d + "<table><caption><b></caption></table>", [.unclosedElement]),
        Case("an end tr with no row", d + "<table><tbody></tr></tbody></table>", [.unexpectedEndTag]),
        Case("a NUL in a table", d + "<table>\u{0}</table>", [.unexpectedNullCharacter]),
        // Templates.
        Case("the end of the input in a template", d + "<template>", [.unexpectedEndOfFile]),
        Case("a stray end tag in a template", d + "<template></span></template>", [.unexpectedEndTag]),
        // After the body and the frameset.
        Case("text after the body", d + "<body></body>x", [.unexpectedCharacter]),
        Case("a tag after the body", d + "<body></body><p>", [.unexpectedStartTag]),
        Case(
            "an end tag after the body (once there, once in the body)",
            d + "<body></body></span>",
            [.unexpectedEndTag, .unexpectedEndTag]
        ),
        Case("text after the end of html", d + "<body></body></html>x", [.unexpectedCharacter]),
        Case("text after the frameset", d + "<frameset></frameset>x", [.unexpectedCharacter]),
        Case(
            "text after the end of html in a frameset document",
            d + "<frameset></frameset></html>x",
            [.unexpectedCharacter]
        ),
        Case("a tag in a frameset", d + "<frameset><p>", [.unexpectedStartTag, .unexpectedEndOfFile]),
        Case("a doctype in a frameset", d + "<frameset><!DOCTYPE html></frameset>", [.unexpectedDoctype]),
        // Foreign content.
        Case("an HTML tag in svg", d + "<svg><p>", [.unexpectedHTMLInForeignContent]),
        Case("an end tag svg does not hold", d + "<svg></g></svg>", [.foreignEndTagMismatch, .unexpectedEndTag]),
        Case("a NUL in svg", d + "<svg>\u{0}</svg>", [.unexpectedNullCharacter]),
        Case("a doctype in svg", d + "<svg><!DOCTYPE html></svg>", [.unexpectedDoctype]),
        Case(
            "a br end tag in svg (which it leaves, so the svg end tag has nothing)",
            d + "<svg></br></svg>",
            [.unexpectedHTMLInForeignContent, .unexpectedEndTag, .unexpectedEndTag]
        )
    ]

    @Test(arguments: cases)
    func `the classes of error a document has`(test: Case) {
        let actual = Self.errors(test.html)
        #expect(actual == test.wanted, "\(test.html.debugDescription) gave \(actual.map(\.rawValue))")
    }

    @Test
    func `every class has a case that gives it`() {
        let seen = Set(Self.cases.flatMap(\.wanted))
        let missing = HTMLTreeError.allCases.filter { !seen.contains($0) }
        #expect(missing.isEmpty, "no case for \(missing)")
    }

    @Test
    func `a self-closing flag nothing acknowledged is the spec's error`() {
        let withFlag = HTMLParser.parse(Array((Self.d + "<div/>").utf8), options: Self.options())
        #expect(withFlag.errors.map(\.code) == [.nonVoidHtmlElementStartTagWithTrailingSolidus])
        let acknowledged = HTMLParser.parse(Array((Self.d + "<br/><svg/><img/><input/>").utf8), options: Self.options())
        #expect(acknowledged.errors.isEmpty)
        // The offset is where the tag starts.
        #expect(withFlag.errors.first?.offset == Self.d.utf8.count + 1)
    }

    @Test
    func `an error is placed at its token`() {
        let html = Self.d + "<body></div>"
        let found = HTMLParser.parse(Array(html.utf8), options: Self.options()).treeErrors
        #expect(found.count == 1)
        #expect(found.first?.offset == html.utf8.count - "div>".utf8.count)
        // Text the tokenizer rewrote (a NUL) has no place in the source; the end of the input is its length.
        let atEnd = HTMLParser.parse(Array((Self.d + "<div>").utf8), options: Self.options()).treeErrors
        #expect(atEnd.first?.offset == (Self.d + "<div>").utf8.count)
    }

    @Test
    func `nothing is kept unless errors were asked for`() {
        let document = HTMLParser.parse(Array((Self.d + "<table>x</div>").utf8))
        #expect(document.treeErrors.isEmpty)
        #expect(document.errors.isEmpty)
    }

    @Test(arguments: cases)
    func `reporting errors does not change the tree`(test: Case) {
        let bytes = Array(test.html.utf8)
        let quiet = Html5libTree.dump(HTMLParser.parse(bytes), fragment: false)
        let loud = Html5libTree.dump(HTMLParser.parse(bytes, options: Self.options()), fragment: false)
        #expect(quiet == loud)
    }

    @Test(arguments: cases)
    func `a stream finds the errors of the whole document`(test: Case) {
        let bytes = Array(test.html.utf8)
        let whole = HTMLParser.parse(bytes, options: Self.options()).treeErrors
        for size in [1, 3, 7] {
            var parser = HTMLStreamParser(options: Self.options())
            var offset = 0
            while offset < bytes.count {
                let end = Swift.min(offset + size, bytes.count)
                parser.feed(Array(bytes[offset ..< end]))
                offset = end
            }
            #expect(parser.finish().treeErrors == whole, "chunks of \(size): \(test.html.debugDescription)")
        }
    }

    @Test
    func `a fragment parse reports too`() {
        var options = Self.options()
        options.collectsErrors = true
        let document = HTMLParser.parseFragment(Array("</div>".utf8), context: "body", options: options)
        #expect(document.treeErrors.map(\.kind) == [.unexpectedEndTag])
    }
}

/// html5lib's lists of errors are its own (576 names, four formats, an idea of where the standard says "parse error" that is older than the standard now), so they are a smoke test and no more:
/// the *number* of errors in a case is compared, not their names. Of the 1,600 cases without a fragment, the counts agree in all but ten, and every one of the ten has a reason.
@Suite(
    "The tree builder's errors against html5lib's lists",
    .enabled(if: !Html5libTree.files(in: Html5libTree.frozenDirectory).isEmpty, "run Scripts/fetch-html5lib.sh")
)
struct TreeErrorCountTests {
    /// (Against the frozen copy of html5lib's tests, whose cases list their errors; the copy web-platform-tests keeps lists none for many.) Cases whose count differs, and why: five new `webkit02` cases whose files list no errors at all; three with `<?...>`, which is a processing instruction now and no error; `<nobr><table><marquee></table>`,
    /// where html5lib counts an element left open that the standard does not; `<math></html>`, where it counts the same end tag twice.
    static let explained: Set<String> = [
        "webkit02.dat#45", "webkit02.dat#46", "webkit02.dat#47", "webkit02.dat#48", "webkit02.dat#49",
        "html5test-com.dat#12", "tests1.dat#44", "tests1.dat#47", "adoption02.dat#3", "tests19.dat#84"
    ]

    @Test func `the counts agree with html5lib's except where the difference is explained`() {
        var total = 0
        var unexplained: [String] = []
        var stale: [String] = []
        for file in Html5libTree.files(in: Html5libTree.frozenDirectory) {
            for test in Html5libTree.cases(in: file, from: Html5libTree.frozenDirectory) where test.fragment == nil {
                var options = HTMLParser.Options()
                options.collectsErrors = true
                if let scripting = test.scripting { options.scripting = scripting }
                let document = HTMLParser.parse(Array(test.data.utf8), options: options)
                let ours = document.errors.count + document.treeErrors.count
                total += 1
                let agrees = ours == test.listedErrors
                if !agrees, !Self.explained.contains(test.id) {
                    unexplained.append(
                        "\(test.id): ours \(ours), theirs \(test.listedErrors) \(test.data.debugDescription.prefix(60))"
                    )
                }
                if agrees, Self.explained.contains(test.id) { stale.append(test.id) }
            }
        }
        #expect(total > 1500, "\(total) cases")
        #expect(
            unexplained.isEmpty,
            Comment(rawValue: "\(unexplained.count) unexplained:\n" + unexplained.prefix(8).joined(separator: "\n"))
        )
        #expect(stale.isEmpty, "these agree now, take them out of `explained`: \(stale)")
    }
}
