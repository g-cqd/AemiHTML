import Testing

@testable import AemiHTML

/// `selectedcontent` mirrors the selected option into itself (HTML Standard 4.10.x), once a parse is over.
@Suite("The selectedcontent element")
struct SelectedContentTests {
    /// The text under each `selectedcontent`, in tree order.
    private func mirrored(_ html: String) -> [String] {
        let document = HTMLParser.parse(Array(("<!DOCTYPE html>" + html).utf8))
        var found: [String] = []
        for node in document.descendants(of: document.root) where document.isElement(node, "selectedcontent") {
            var text = ""
            for inner in document.descendants(of: node) where document.kind(inner) == .text {
                text += String(decoding: document.data(inner), as: UTF8.self)
            }
            found.append(text)
        }
        return found
    }

    @Test func `the first option is selected when none says so`() {
        #expect(mirrored("<select><button><selectedcontent></button><option>A<option>B</select>") == ["A"])
    }

    @Test func `the last option with selected wins`() {
        #expect(
            mirrored("<select><button><selectedcontent></button><option selected>A<option selected>B<option>C</select>")
                == ["B"]
        )
    }

    @Test func `a disabled first option is passed over`() {
        #expect(mirrored("<select><button><selectedcontent></button><option disabled>A<option>B</select>") == ["B"])
        #expect(
            mirrored(
                "<select><button><selectedcontent></button><optgroup disabled><option>A</optgroup><option>B</select>"
            ) == ["B"]
        )
    }

    @Test func `options inside an optgroup count, markup is copied`() {
        #expect(
            mirrored("<select><button><selectedcontent></button><optgroup><option>A <b>bold</b></optgroup></select>")
                == ["A bold"]
        )
    }

    @Test func `a select with multiple is not mirrored`() {
        #expect(mirrored("<select multiple><button><selectedcontent></button><option>A</select>") == [""])
    }

    @Test func `a display size above one selects nothing by itself`() {
        #expect(mirrored("<select size=3><button><selectedcontent></button><option>A</select>") == [""])
        #expect(
            mirrored("<select size=3><button><selectedcontent></button><option selected>A<option>B</select>") == ["A"]
        )
    }

    @Test func `a selectedcontent in an option or a nested one is left alone`() {
        #expect(mirrored("<select><option>A<selectedcontent></selectedcontent></select>") == [""])
    }

    @Test func `outside a select nothing is copied`() {
        #expect(mirrored("<div><selectedcontent>kept</selectedcontent></div>") == ["kept"])
    }

    @Test func `two of them under one select both get the copy`() {
        #expect(
            mirrored(
                "<select><button><selectedcontent></button><div><selectedcontent></selectedcontent></div><option>A</select>"
            ) == ["A", "A"]
        )
    }

    @Test func `many copies of a big option stay inside the budget`() {
        let option = String(repeating: "<i>x</i>", count: 5_000)
        let html =
            "<select><button>" + String(repeating: "<selectedcontent></selectedcontent>", count: 5_000)
            + "</button><option>" + option + "</select>"
        let document = HTMLParser.parse(Array(html.utf8))
        // The copies stop at the size of the document: not 5,000 times 10,000 nodes.
        #expect(document.nodeCount < 200_000)
    }
}
