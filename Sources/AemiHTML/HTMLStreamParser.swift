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
    private var builder: HTMLTreeBuilder
    private var preparer = HTMLChunkPreparer(dropsByteOrderMark: true)
    /// The number of bytes fed so far.
    public private(set) var bytesFed = 0
    /// The bytes the tokenizer has read, and how many were there when a step was last undone: a token that does not complete is not tried again until half as much again has come.
    private var triedAt = 0
    private var retryAfter = 0
    private var isFinished = false
    private var scannedErrors = 0

    public init(options: HTMLParser.Options = HTMLParser.Options()) {
        builder = HTMLParser.makeStreamingBuilder(options)
    }

    /// Gives the parser the next piece of the document (UTF-8; for other encodings, decode first).
    public mutating func feed(_ chunk: [UInt8]) {
        guard !isFinished, !chunk.isEmpty else { return }
        bytesFed += chunk.count
        append(preparer.prepare(chunk, final: false))
        let available = builder.tokenizer.count
        guard available - triedAt >= retryAfter else { return }
        run(final: false)
    }

    /// The document, once the last piece has been fed. The parser cannot be used afterwards.
    public mutating func finish() -> HTMLDocument {
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

extension HTMLParser {
    static func makeStreamingBuilder(_ options: Options) -> HTMLTreeBuilder {
        var tokenizerOptions = HTMLTokenizer.Options()
        tokenizerOptions.switchesContentModel = false
        tokenizerOptions.collectsErrors = options.collectsErrors
        var tokenizer = HTMLTokenizer(input: [], options: tokenizerOptions, out: HTMLTokens(source: []))
        tokenizer.isFinal = false
        var builder = HTMLTreeBuilder(tokenizer: tokenizer, scripting: options.scripting, maxDepth: options.maxDepth)
        builder.collectsErrors = options.collectsErrors
        return builder
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
