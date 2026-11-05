import Testing

@testable import AemiHTML

@Suite("The preorder view")
struct PreorderTests {
    private func parse(_ html: String) -> HTMLDocument { HTMLParser.parse(Array(html.utf8)) }

    /// A page of nested lists, tables, formatting that the builder rearranges, a template and a deep run: shapes where the arena's order is not document order.
    private static let samples = [
        "<!DOCTYPE html><html><head><title>t</title></head><body><p>a<b>b<i>c</b>d</i>e</p></body></html>",
        "<table><tr><td>x<table><tr><td>y</table><div>foster</div></table>",
        "<ul><li>a<ul><li>b<li>c</ul><li>d</ul><template><p>in</template><svg><g><path/></g></svg>",
        "<div><span>a</span><!--c--><span>b</span>text<br>more</div>",
        ""
    ]

    @Test(arguments: samples)
    func `the order is the order of descendants`(html: String) {
        let document = parse(html)
        let view = document.preorder()
        let walked = [document.root] + Array(document.descendants(of: document.root))
        #expect(view.nodes == walked)
        #expect(view.count == walked.count)
    }

    @Test(arguments: samples)
    func `each subtree is the range of its descendants`(html: String) {
        let document = parse(html)
        let view = document.preorder()
        for index in 0 ..< view.count {
            let node = view.nodes[index]
            let expected = Array(document.descendants(of: node))
            let range = view.descendants(of: index)
            #expect(Array(view.nodes[range]) == expected, "node \(index)")
            #expect(view.subtree(of: index).count == expected.count + 1)
            #expect(view.index(of: node) == index)
        }
    }

    @Test(arguments: samples)
    func `depth and parent agree with the tree`(html: String) {
        let document = parse(html)
        let view = document.preorder()
        #expect(view.parentIndex(of: 0) == nil)
        #expect(view.depth[0] == 0)
        for index in 1 ..< view.count {
            let parent = document.parent(view.nodes[index])
            #expect(view.parentIndex(of: index).map { view.nodes[$0] } == parent)
            #expect(Int(view.depth[index]) == Int(view.depth[view.parentIndex(of: index)!]) + 1)
        }
    }

    @Test func `a node taken out of the tree is not in the view`() {
        var document = parse("<div><p>a</p><p>b</p></div>")
        let view = document.preorder()
        let victim = view.nodes[view.count - 1]
        #expect(view.index(of: victim) != nil)
        document.detach(victim)
        let after = document.preorder()
        #expect(after.index(of: victim) == nil)
        #expect(after.count < view.count)
    }

    @Test func `a tree nested very deep is walked without recursion`() {
        // Made in the arena directly (the builder bounds the depth, and its scope checks are linear in it): a chain of 300,000 elements, each the only child of the one before.
        var document = HTMLDocument(source: [], scratch: [])
        var parent = document.root
        for _ in 0 ..< 300_000 {
            let node = document.makeNode(.element, name: .div, space: .html)
            document.append(node, to: parent)
            parent = node
        }
        let view = document.preorder()
        #expect(view.count == document.nodeCount)
        #expect(view.depth[view.count - 1] == 300_000)
        #expect(view.descendants(of: 0).count == 300_000)
        #expect(view.parentIndex(of: view.count - 1) == view.count - 2)
    }

    @Test func `an index from another document is no node here`() {
        let small = parse("<p>a")
        let big = parse("<div><p>a</p><p>b</p><p>c</p></div>")
        let view = small.preorder()
        let foreign = big.preorder().nodes[big.nodeCount - 1]
        #expect(view.index(of: foreign) == nil)
        #expect(view.index(of: .none) == nil)
    }
}
