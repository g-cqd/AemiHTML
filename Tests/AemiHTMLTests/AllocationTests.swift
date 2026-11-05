import AemiTestKit
import Testing

@testable import AemiHTML

private let isDebugBuild: Bool = {
    #if DEBUG
        true
    #else
        false
    #endif
}()

/// What the README says: no object per token and none per node. A document a hundred times larger may allocate a few more times (an array that grows), never in proportion to its tokens or nodes. The ceilings describe the optimized
/// build (`swift test -c release`); AemiTestKit counts through libmalloc's hook, so this runs on macOS.
@Suite(
    "Parsing does not allocate per token or per node",
    .serialized,
    .disabled(if: isDebugBuild, "the ceilings describe the optimized build; run them with -c release"),
    .enabled(if: allocationCountingAvailable, "allocations are counted on Darwin only, and not under a sanitizer")
)
struct AllocationTests {
    static let unit = """
        <!DOCTYPE html><html><head><title>t &amp; u</title><style>p { color: red }</style><script>if (a < b) { x() }</script></head>
        <body class="a b" id=main data-x='1'><!-- note --><h1>Title &copy; 2026</h1><p>One <b>bold <i>both</b> italic</i> <a href="/x?a=1&amp;b=2">link</a>
        <table><tr><td>cell<td>cell</table><ul><li>a<li>b</ul><svg viewBox="0 0 1 1"><path d="M0 0"/></svg><br><img src=x alt="y"><pre>
        code &lt; here</pre></body></html>

        """

    static func document(repeating count: Int) -> [UInt8] { Array(String(repeating: unit, count: count).utf8) }

    @Test func `tokenizing a hundred times as much allocates a handful of times more`() throws {
        let small = Self.document(repeating: 10)
        let large = Self.document(repeating: 1000)
        _ = HTMLTokenizer.tokenize(small)
        let few = try #require(mallocDelta { _ = HTMLTokenizer.tokenize(small) })
        let many = try #require(mallocDelta { _ = HTMLTokenizer.tokenize(large) })
        #expect(many <= few + 40, "\(few) allocations for 10 copies, \(many) for 1000")
    }

    @Test func `parsing a hundred times as much allocates a handful of times more`() throws {
        let small = Self.document(repeating: 10)
        let large = Self.document(repeating: 1000)
        _ = HTMLParser.parse(small)
        let few = try #require(mallocDelta { _ = HTMLParser.parse(small) })
        let many = try #require(mallocDelta { _ = HTMLParser.parse(large) })
        #expect(many <= few + 60, "\(few) allocations for 10 copies, \(many) for 1000")
    }
}

@Suite(
    "Each construct, parsed again and again, allocates nothing more",
    .serialized,
    .disabled(if: isDebugBuild, "the ceilings describe the optimized build; run them with -c release"),
    .enabled(if: allocationCountingAvailable, "allocations are counted on Darwin only, and not under a sanitizer")
)
struct ConstructAllocationTests {
    @Test(arguments: [
        "plain text ", "<p>x", "<b>x</b>", "<b>1<p>2</b>3", "<a href=\"/x?a=1&amp;b=2\">l</a>",
        "<div class=a id=b>x</div>", "<!-- c -->", "&amp; &copy; &#x41;",
        "<table><tr><td>c</table>", "x<table>y<tr><td>z</table>", "<ul><li>a<li>b</ul>",
        "<svg viewBox=\"0\"><path d=\"M0\"/></svg>", "<br><img src=x>",
        "<pre>\ncode</pre>", "<script>if (a < b) {}</script>", "<title>t</title>",
        "<select><option>a<option>b</select>", "<template><p>x</template>",
        "<h1>t</h1><h2>u</h2>", "<form><input type=hidden></form>", "<dl><dt>a<dd>b</dl>", "<textarea>\nx</textarea>",
        "<math><mi>x</mi></math>",
        "<button>a<button>b", "<i><b><i><b>x", "<svg viewBox=\"0\">", "<svg a=\"0\">", "<svg><path/></svg>",
        "<svg><path d=M0/></svg>", "<svg></svg>", "<svg><g></g></svg>", "<font color=red>", "<font>x", "<b x=1>y",
        "<p>x", "<input type=hidden>", "<form>", "<svg>", "<path d=M0 />", "<math>", "<mi>x", "<table>", "<table><tr>",
        "<table>y", "<td>z", "<div>x</div>", "<font color=red><p>x", "<center><nobr>a<nobr>b", "<?php x ?>",
        "<!DOCTYPE html>"
    ])
    func `a construct repeated allocates nothing in proportion`(snippet: String) throws {
        let small = Array(("<body>" + String(repeating: snippet, count: 10)).utf8)
        let large = Array(("<body>" + String(repeating: snippet, count: 1000)).utf8)
        _ = HTMLParser.parse(small)
        let few = try #require(mallocDelta { _ = HTMLParser.parse(small) })
        let many = try #require(mallocDelta { _ = HTMLParser.parse(large) })
        #expect(many <= few + 40, "\(snippet.debugDescription): \(few) allocations for 10, \(many) for 1000")
    }
}
