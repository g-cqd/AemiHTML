internal import AemiKernel
internal import AemiKernels

/// The HTML parser: the tokenizer (13.2.5) and the tree builder (13.2.6) of the WHATWG HTML Standard over UTF-8 bytes, into an arena `HTMLDocument`. No recursion anywhere; the depth of the tree is bounded.
///
/// ```swift
/// let document = HTMLParser.parse(Array("<p>one<p>two".utf8))
/// for node in document.descendants(of: document.root) where document.kind(node) == .element { print(String(decoding: document.name(node), as: UTF8.self)) }
/// ```
public enum HTMLParser {
    public struct Options: Sendable {
        public init() {}

        /// The scripting flag: with it on, `noscript` holds text; off (the default, as for a reader that runs nothing), its content is parsed as markup.
        public var scripting = false
        /// Record the tokenizer's parse errors in `HTMLDocument.errors`.
        public var collectsErrors = false
        /// The deepest the stack of open elements may grow. Past it an element is inserted but not opened (its children go to its parent), which keeps every pass linear in the input; real documents nest a few dozen deep.
        public var maxDepth = 512
    }

    /// Parses a document.
    public static func parse(_ input: [UInt8], options: Options = Options()) -> HTMLDocument {
        var builder = HTMLTreeBuilder(
            tokenizer: makeTokenizer(input, options, state: .data),
            scripting: options.scripting,
            maxDepth: options.maxDepth
        )
        builder.run()
        return builder.document
    }

    /// Parses `input` as the children of an element named `context` in `namespace` (the HTML fragment parsing algorithm, 13.4: what `innerHTML` does). The result is in `HTMLDocument.fragmentRoot`.
    public static func parseFragment(
        _ input: [UInt8],
        context: String,
        namespace: HTMLDocument.Namespace = .html,
        options: Options = Options()
    ) -> HTMLDocument {
        let name = HTMLName.lookup(ArraySlice(context.utf8.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }))
        var state = HTMLTokenizer.InitialState.data
        if namespace == .html {
            switch name {
                case .title, .textarea: state = .rcdata
                case .style, .xmp, .iframe, .noembed, .noframes: state = .rawtext
                case .script: state = .scriptData
                case .noscript where options.scripting: state = .rawtext
                case .plaintext: state = .plaintext
                default: break
            }
        }
        var builder = HTMLTreeBuilder(
            tokenizer: makeTokenizer(input, options, state: state),
            scripting: options.scripting,
            maxDepth: options.maxDepth
        )
        builder.setUpFragment(context: context, name: name, namespace: namespace)
        builder.run()
        return builder.document
    }

    private static func makeTokenizer(_ input: [UInt8], _ options: Options, state: HTMLTokenizer.InitialState)
        -> HTMLTokenizer
    {
        var tokenizerOptions = HTMLTokenizer.Options()
        tokenizerOptions.initialState = state
        tokenizerOptions.switchesContentModel = false
        tokenizerOptions.collectsErrors = options.collectsErrors
        var bytes = input.count > TapeSlot.maxLow ? Array(input.prefix(TapeSlot.maxLow)) : input
        if AemiKernels.firstIndexOfByte(0x0D, in: bytes) != nil { bytes = HTMLTokenizer.normalizedNewlines(bytes) }
        var out = HTMLTokens(source: bytes)
        out.tape.reserveCapacity(bytes.count / 12 + 16)
        var tokenizer = HTMLTokenizer(input: bytes, options: tokenizerOptions, out: out)
        if options.collectsErrors { tokenizer.scanInputErrors() }
        return tokenizer
    }
}

extension HTMLTreeBuilder {
    /// 13.4: the stack holds one new `html` element, the context element is remembered (the "fake" start tag is not needed here), and the insertion mode is chosen from the context.
    mutating func setUpFragment(context: String, name: HTMLName, namespace: HTMLDocument.Namespace) {
        document.source = tokenizer.out.source
        let contextNode = document.makeNode(
            .element,
            name: name,
            space: namespace,
            nameRange: tokenizer.out.intern(utf8: context)
        )
        if name == .template, namespace == .html {
            document.append(document.makeNode(.templateContents), to: contextNode)
        }
        contextElement = contextNode
        let root = document.makeNode(.element, name: .html, space: .html, nameRange: tokenizer.out.intern(utf8: "html"))
        document.append(root, to: document.root)
        document.fragmentRoot = root
        stack = [root]
        if name == .template, namespace == .html { templateModes.append(.inTemplate) }
        resetInsertionMode()
    }
}
