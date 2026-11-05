internal import AemiKernel

/// A parser that is given a document a piece at a time. The tree it makes is the tree `HTMLParser.parse` makes of the pieces joined, wherever they are cut (checked on every cut of the html5lib cases, and of real pages); what a piece adds is there as soon as it is fed, except what the
/// standard cannot settle before it sees more: a tag, a comment, a character reference that the piece ends inside.
///
/// ```swift
/// var parser = HTMLStreamParser()
/// for chunk in chunks { parser.feed(chunk) }          // each chunk: [UInt8]
/// let document = parser.finish()
/// ```
public struct HTMLStreamParser {
    /// The engine, one of two kinds (a builder that keeps parse errors and one that does not). It is held as an existential, which stores a struct this size in a box of its own that the parser alone owns, so each call works on it in place: copying it out and back on every piece would make the input's buffer shared, and the append would copy it.
    private var engine: any StreamingEngine

    /// The number of bytes fed so far.
    public var bytesFed: Int { engine.bytesFed }

    public init(options: HTMLParser.Options = HTMLParser.Options()) {
        engine =
            options.collectsErrors
            ? StreamEngine<LoudErrors>(options, fragment: nil) : StreamEngine<QuietErrors>(options, fragment: nil)
    }

    /// A parser for the children of an element named `context` in `namespace` (the HTML fragment parsing algorithm, 13.4: what `innerHTML` does), given a piece at a time. The result is in `HTMLDocument.fragmentRoot`, as `HTMLParser.parseFragment` leaves it, and is the same wherever the pieces are cut.
    public init(
        fragmentContext context: String,
        namespace: HTMLDocument.Namespace = .html,
        options: HTMLParser.Options = HTMLParser.Options()
    ) {
        let fragment = StreamFragment(context: context, namespace: namespace)
        engine =
            options.collectsErrors
            ? StreamEngine<LoudErrors>(options, fragment: fragment)
            : StreamEngine<QuietErrors>(options, fragment: fragment)
    }

    /// Gives the parser the next piece of the document (UTF-8; for other encodings, decode first).
    public mutating func feed(_ chunk: [UInt8]) { engine.feed(chunk) }

    /// The document, once the last piece has been fed. The parser cannot be used afterwards.
    public mutating func finish() -> HTMLDocument { engine.finish() }
}

/// What makes a stream a fragment parse: the context element's name and namespace.
struct StreamFragment {
    var context: String
    var namespace: HTMLDocument.Namespace
}

protocol StreamingEngine {
    var bytesFed: Int { get }
    mutating func feed(_ chunk: [UInt8])
    mutating func finish() -> HTMLDocument
}

struct StreamEngine<Reporting: TreeErrorReporting>: StreamingEngine {
    private var builder: HTMLTreeBuilder<Reporting>
    private var preparer = HTMLChunkPreparer(dropsByteOrderMark: true)
    private(set) var bytesFed = 0
    /// The bytes the tokenizer has read, and how many were there when a step was last undone: a token that does not complete is not tried again until half as much again has come.
    private var triedAt = 0
    private var retryAfter = 0
    private var isFinished = false
    private var scannedErrors = 0

    init(_ options: HTMLParser.Options, fragment: StreamFragment?) {
        var tokenizerOptions = HTMLTokenizer.Options()
        tokenizerOptions.switchesContentModel = false
        tokenizerOptions.collectsErrors = options.collectsErrors
        var name = HTMLName.unknown
        if let fragment {
            (name, tokenizerOptions.initialState) = HTMLParser.fragmentContext(
                fragment.context,
                namespace: fragment.namespace,
                options: options
            )
        }
        var tokenizer = HTMLTokenizer(input: [], options: tokenizerOptions, out: HTMLTokens(source: []))
        tokenizer.isFinal = false
        builder = HTMLTreeBuilder<Reporting>(
            tokenizer: tokenizer,
            scripting: options.scripting,
            maxDepth: options.maxDepth
        )
        if let fragment { builder.setUpFragment(context: fragment.context, name: name, namespace: fragment.namespace) }
    }

    mutating func feed(_ chunk: [UInt8]) {
        guard !isFinished, !chunk.isEmpty else { return }
        bytesFed += chunk.count
        append(preparer.prepare(chunk, final: false))
        let available = builder.tokenizer.count
        guard available - triedAt >= retryAfter else { return }
        run(final: false)
    }

    mutating func finish() -> HTMLDocument {
        if !isFinished {
            append(preparer.prepare([], final: true))
            isFinished = true
            run(final: true)
        }
        return builder.document
    }

    private mutating func run(final: Bool) {
        let undone = builder.runStreaming(final: final)
        triedAt = builder.tokenizer.count
        retryAfter = undone ? Swift.max(1, (triedAt - builder.tokenizer.streamMark.pos) / 2) : 0
    }

    /// Adds settled bytes to the input. The two arrays that hold it (the tokenizer's and the tokens') are emptied first so that the append finds the buffer alone and does not copy it.
    private mutating func append(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        var buffer = builder.tokenizer.input
        builder.tokenizer.input = []
        builder.tokenizer.out.source = []
        buffer.append(contentsOf: bytes.prefix(Swift.max(0, TapeSlot.maxLow - buffer.count)))
        builder.tokenizer.input = buffer
        builder.tokenizer.out.source = buffer
        builder.tokenizer.count = buffer.count
        if builder.collectsErrors {
            builder.tokenizer.scanInputErrors(from: scannedErrors)
            scannedErrors = buffer.count
        }
    }
}

extension HTMLTreeBuilder {
    /// Processes what the input so far makes tokens of. With `final`, the input is all there is: the machine runs to the end, the end-of-file token is processed, and the document is finished.
    mutating func runStreaming(final: Bool) -> Bool {
        var undone = false
        tokenizer.isFinal = final
        while true {
            let adjusted = stack.isEmpty ? Node.none : adjustedCurrentNode
            tokenizer.allowsCDATA = !adjusted.isNone && space(of: adjusted) != .html
            if tokenizer.advanceStreaming() { undone = true }
            readBatch()
            if tokenizer.done || tokenizer.needMore { break }
        }
        if final {
            process(BuilderToken(kind: .endOfFile))
            finish()
        }
        return undone
    }
}
