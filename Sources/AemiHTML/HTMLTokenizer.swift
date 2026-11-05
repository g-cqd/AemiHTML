internal import AemiKernel
internal import AemiKernels

/// An HTML tokenizer: the WHATWG HTML Standard's tokenization stage (13.2.5) over UTF-8 bytes, in one pass, with no recursion and no failure (any bytes give tokens). It is checked against the
/// html5lib tokenizer tests (`Tests/AemiHTMLTests`, which fetch them), and it allocates nothing per token.
///
/// ```swift
/// let tokens = HTMLTokenizer.tokenize(Array("<p class=a>Hi &amp; bye".utf8))
/// for token in tokens.tokens where token.kind == .startTag { print(String(decoding: token.name, as: UTF8.self)) }
/// ```
public struct HTMLTokenizer {
    /// The states a tokenizer can start in: the content models the tree-construction stage switches between.
    public enum InitialState: Sendable {
        case data, rcdata, rawtext, scriptData, plaintext, cdataSection
    }

    public struct Options: Sendable {
        public init() {}

        public var initialState = InitialState.data
        /// The name of the last start tag, which an end tag must repeat to end RCDATA, RAWTEXT and script data (lower case).
        public var lastStartTag: [UInt8] = []
        /// Switch to RCDATA, RAWTEXT, script data or PLAINTEXT after the start tags that need it (`title`, `style`, `script`, ...), as a tree builder would.
        public var switchesContentModel = true
        /// Whether `<![CDATA[` opens a CDATA section (foreign content) or a bogus comment (HTML content).
        public var allowsCDATA = false
        /// Record the parse errors (a little slower).
        public var collectsErrors = false
    }

    enum State: UInt8 {
        case data, rcdata, rawtext, scriptData, plaintext, cdata
        case tagOpen, endTagOpen, tagName, beforeAttributeName, attributeName, afterAttributeName
        case beforeAttributeValue, attributeValueQuoted, attributeValueUnquoted, afterAttributeValueQuoted
        case selfClosingStartTag, markupDeclarationOpen
        case processingInstructionOpen, processingInstructionTarget, afterProcessingInstructionTarget,
            processingInstructionData
        case bogusComment, commentStart, commentStartDash, comment, commentEndDash, commentEnd, commentEndBang
        case doctype, beforeDoctypeName, doctypeName, afterDoctypeName
        case afterDoctypePublicKeyword, beforeDoctypePublicIdentifier, doctypePublicIdentifier
        case afterDoctypePublicIdentifier, betweenDoctypeIdentifiers
        case afterDoctypeSystemKeyword, beforeDoctypeSystemIdentifier, doctypeSystemIdentifier
        case afterDoctypeSystemIdentifier, bogusDoctype
    }

    let input: [UInt8]
    let count: Int
    let options: Options
    /// Whether `<![CDATA[` opens a CDATA section: the tree builder sets it while the adjusted current node is in a foreign namespace.
    var allowsCDATA: Bool
    /// Set by every token that ends a batch for `advance()`: a tag, comment, doctype or processing instruction.
    var batchReady = false
    var pos = 0
    var state: State
    var done = false
    var out: HTMLTokens
    /// The name of the last start tag the tokenizer made, as a range of the source or the scratch (an end tag must repeat it to end RCDATA, RAWTEXT and script data).
    var lastStartTagRange: UInt64 = 0

    // The tag being read.
    var tagIsEnd = false
    var tagSlot = 0
    var attributeCount = 0
    var attributeHashes: Set<UInt64> = []
    var valueSlot = 0
    var attributeIsDuplicate = false
    var attributeValueQuote: UInt8 = 0
    var attributeNameStart = 0
    // The comment or doctype being read: where its data starts, and where it ends so far.
    var dataStart = 0
    var dataEnd = 0
    var doctypeFlags = HTMLDoctypeFlags()
    var doctypeSlot = 0
    var tagStart = 0
    var targetStart = 0
    var targetEnd = 0

    /// The tokens of `input`. Input over 4 GiB is cut there (a slot's offset is 32 bits).
    public static func tokenize(_ input: [UInt8], options: Options = Options()) -> HTMLTokens {
        var bytes = input.count > TapeSlot.maxLow ? Array(input.prefix(TapeSlot.maxLow)) : input
        if AemiKernels.firstIndexOfByte(0x0D, in: bytes) != nil { bytes = normalizedNewlines(bytes) }
        var result = HTMLTokens(source: bytes)
        let count = bytes.count
        result.tape.reserveCapacity(count / 16 + 16)
        var machine = HTMLTokenizer(input: bytes, options: options, out: result)
        if options.collectsErrors { machine.scanInputErrors() }
        machine.run()
        result = machine.out
        return result
    }

    /// CR LF and CR become LF (13.2.3.5), before tokenization.
    static func normalizedNewlines(_ bytes: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x0D {
                result.append(0x0A)
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A { index += 1 }
            } else {
                result.append(byte)
            }
            index += 1
        }
        return result
    }

    init(input: [UInt8], options: Options, out: HTMLTokens) {
        self.input = input
        count = input.count
        self.options = options
        self.out = out
        allowsCDATA = options.allowsCDATA
        self.out = out
        lastStartTagRange = self.out.intern(options.lastStartTag)
        switch options.initialState {
            case .data: state = .data
            case .rcdata: state = .rcdata
            case .rawtext: state = .rawtext
            case .scriptData: state = .scriptData
            case .plaintext: state = .plaintext
            case .cdataSection: state = .cdata
        }
    }
}
