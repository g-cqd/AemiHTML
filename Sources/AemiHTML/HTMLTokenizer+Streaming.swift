/// A tokenizer that is given its input a piece at a time (`HTMLStreamParser`). The tokens are the ones the whole input would make, however it is cut; the way it is done is the simplest that is sure of it:
///
/// - at the start of every token, in a text state, the tokenizer notes where it is (`mark`);
/// - a step that looks at a byte past the end of the input so far, or decides something by the input ending (every place the machine treats the end as the end of the document says so with `reachedEnd()`), is **undone**: the tape, the scratch and the
///   errors go back to the mark, and the machine waits for more bytes;
/// - a text state that reaches the end with nothing pending has made complete tokens, and keeps them: the text so far is there at once, and what follows will be another slot (`sealed`: a slot the tree builder has read is never added to).
///
/// The driver (`HTMLStreamParser`) does not run the machine again for every byte: after a step was undone it waits until half as many bytes again have come, so a token of any size, fed a byte at a time, costs a linear amount.
extension HTMLTokenizer {
    /// Where a token began: what undoing a step puts back.
    struct Mark {
        var pos = 0
        var state = State.data
        var tapeCount = 0
        var scratchCount = 0
        var errorCount = 0
        /// The last slot of the tape then: a text run is extended in place, and undoing has to un-extend it.
        var lastSlot: UInt64 = 0
        var lastStartTagRange: UInt64 = 0
    }

    func currentMark() -> Mark {
        Mark(
            pos: pos,
            state: state,
            tapeCount: out.tape.count,
            scratchCount: out.scratch.count,
            errorCount: out.errors.count,
            lastSlot: out.tape.last ?? 0,
            lastStartTagRange: lastStartTagRange
        )
    }

    mutating func undo(to mark: Mark) {
        pos = mark.pos
        state = mark.state
        out.tape.removeLast(out.tape.count - mark.tapeCount)
        if mark.tapeCount > 0 { out.tape[mark.tapeCount - 1] = mark.lastSlot }
        out.scratch.removeLast(out.scratch.count - mark.scratchCount)
        out.errors.removeLast(out.errors.count - mark.errorCount)
        lastStartTagRange = mark.lastStartTagRange
        done = false
        batchReady = false
    }

    var isTextState: Bool {
        switch state {
            case .data, .rcdata, .rawtext, .scriptData, .plaintext, .cdata: true
            default: false
        }
    }

    /// As `advance()`, for input that may not be all there is: runs until a batch is ready, the document is over (`isFinal`), or the input so far is used up (`needMore`). Returns whether a step was undone, which is when waiting for a good many more bytes pays.
    mutating func advanceStreaming() -> Bool {
        batchReady = false
        needMore = false
        var undone = false
        streamMark = currentMark()
        while !done, !batchReady, !needMore {
            if isTextState { streamMark = currentMark() }
            touchedEnd = false
            step()
            if touchedEnd, !isFinal {
                undo(to: streamMark)
                needMore = true
                undone = true
            }
        }
        sealed = out.tape.count
        return undone
    }

    /// In a text state, after text was emitted: what follows (a `<`, a `&`) is a new token, which is undone to here and no further.
    mutating func markAfterText() {
        if !isFinal { streamMark = currentMark() }
    }
}

extension HTMLTokenizer {
    /// The tokens of `input` read as a stream cut at `cuts` (offsets in the bytes as given, ascending): for tests, which hold the result to what `tokenize` makes of the whole.
    static func tokenizeStreaming(_ input: [UInt8], options: Options = Options(), cuts: [Int]) -> HTMLTokens {
        var tokenizer = HTMLTokenizer(input: [], options: options, out: HTMLTokens(source: []))
        tokenizer.isFinal = false
        var preparer = HTMLChunkPreparer(dropsByteOrderMark: false)
        var scanned = 0
        func feed(_ piece: [UInt8], final: Bool) {
            let settled = preparer.prepare(piece, final: final)
            var buffer = tokenizer.input
            tokenizer.input = []
            tokenizer.out.source = []
            buffer.append(contentsOf: settled)
            tokenizer.input = buffer
            tokenizer.out.source = buffer
            tokenizer.count = buffer.count
            if options.collectsErrors {
                tokenizer.scanInputErrors(from: scanned)
                scanned = buffer.count
            }
            tokenizer.isFinal = final
            while true {
                _ = tokenizer.advanceStreaming()
                if tokenizer.done || tokenizer.needMore { break }
            }
        }
        var start = 0
        for cut in cuts + [input.count] where cut > start && cut <= input.count {
            feed(Array(input[start ..< cut]), final: false)
            start = cut
        }
        feed([], final: true)
        return tokenizer.out
    }
}
