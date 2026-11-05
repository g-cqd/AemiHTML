extension HTMLExtractor {
    /// The element that holds the main text of a page, found by how much text it has and how little of that is in links: the fallback for a page that names no container (`main`, `article`, `[role=main]`, `#content`...).
    ///
    /// Navigation, link lists, tag clouds and "related articles" are mostly links; an article is mostly text. For each element that may hold the page (`body`, `main`, `article`, `section`, `div`, `td`, `form`, `center`), with `T` the bytes of text under it and `L` the bytes of that text inside links
    /// (what the extraction drops as chrome or as hidden is counted in neither), the score is `(T - L) * (1 - L / T)`: the text that is not a link, scaled down by the share that is. The `body` of a page with a link-heavy sidebar scores below the `div` that holds the article,
    /// since the sidebar adds to its `L` and not to its text that counts. Among the elements within a tenth of the best score, the smallest is taken, so a wrapper that adds nothing is not preferred to what it wraps.
    ///
    /// A page of parallel blocks (a home page of promotions) has no one element that is the content, and the densest of them would stand for a fraction of it: a pick that holds less than `minimumShare` of the page's text that is not a link is not taken, and the answer is nil (the caller keeps the `body`).
    ///
    /// One pass over the preorder view, prefix sums, and one look at each candidate: linear in the size of the document. Nil when no element has `minimumText` bytes of text, or none holds `minimumShare` of the page's.
    public static func densestContainer(
        in document: HTMLDocument,
        dropsHiddenContent: Bool = true,
        minimumText: Int = 200,
        minimumShare: Double = 0.5
    ) -> HTMLDocument.Node? {
        let view = document.preorder()
        let count = view.count
        // Prefix sums of the text bytes, and of those inside links, over the positions of the view.
        var text = [Int](repeating: 0, count: count + 1)
        var linked = [Int](repeating: 0, count: count + 1)
        var linkEnd = 0
        var index = 0
        var skipped = [Bool](repeating: false, count: count)
        while index < count {
            let node = view.nodes[index]
            switch document.kind(node) {
                case .element:
                    if document.isDropped(node, hidden: dropsHiddenContent) {
                        // Everything under it counts for nothing: the sums are carried over its whole subtree.
                        let end = Int(view.subtreeEnd[index])
                        for skip in index ..< end {
                            text[skip + 1] = text[skip]
                            linked[skip + 1] = linked[skip]
                            skipped[skip] = true
                        }
                        index = end
                        continue
                    }
                    if document.namespace(node) == .html, HTMLName(rawValue: document.atom(node)) == .a {
                        linkEnd = Swift.max(linkEnd, Int(view.subtreeEnd[index]))
                    }
                    text[index + 1] = text[index]
                    linked[index + 1] = linked[index]
                case .text:
                    let length = document.data(node).count
                    text[index + 1] = text[index] + length
                    linked[index + 1] = linked[index] + (index < linkEnd ? length : 0)
                default:
                    text[index + 1] = text[index]
                    linked[index + 1] = linked[index]
            }
            index += 1
        }
        var best = -1.0
        var scores: [(index: Int, score: Double, text: Int)] = []
        for position in 0 ..< count where !skipped[position] && mayHoldPage(document, view.nodes[position]) {
            let end = Int(view.subtreeEnd[position])
            let total = text[end] - text[position]
            guard total >= minimumText else { continue }
            let links = linked[end] - linked[position]
            let score = Double(total - links) * (1 - Double(links) / Double(total))
            scores.append((position, score, total))
            best = Swift.max(best, score)
        }
        guard best > 0 else { return nil }
        guard
            let chosen = scores.filter({ $0.score >= best * 0.9 })
                .min(by: { ($0.text, $1.index) < ($1.text, $0.index) })
        else { return nil }
        // The share is of the text that is not a link, the whole page's against the pick's.
        let pageText = text[count] - linked[count]
        let end = Int(view.subtreeEnd[chosen.index])
        let chosenText = (text[end] - text[chosen.index]) - (linked[end] - linked[chosen.index])
        guard pageText > 0, Double(chosenText) >= minimumShare * Double(pageText) else { return nil }
        return view.nodes[chosen.index]
    }

    /// The elements a page's main text may be wrapped in.
    private static func mayHoldPage(_ document: HTMLDocument, _ node: HTMLDocument.Node) -> Bool {
        guard document.kind(node) == .element, document.namespace(node) == .html else { return false }
        switch HTMLName(rawValue: document.atom(node)) ?? .unknown {
            case .body, .main, .article, .section, .div, .td, .form, .center: return true
            default: return false
        }
    }
}
