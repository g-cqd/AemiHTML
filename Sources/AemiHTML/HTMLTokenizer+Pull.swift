internal import AemiKernel

extension HTMLTokenizer {
    /// Runs the machine until a tag, a comment, a doctype or a processing instruction has been made (text before it comes with it), or the input is used up. The tree builder drives the tokenizer this way
    /// (13.2.4: the tokenizer's state is switched by the tree builder between tokens, never inside one), so everything on the tape when this returns is final. Returns whether tokens remain to be read.
    mutating func advance() -> Bool {
        batchReady = false
        while !done, !batchReady { step() }
        return !done || out.tape.count > 0
    }

    /// The content models the tree builder switches to after a start tag (13.2.6.2 and the rules of the insertion modes).
    mutating func switchTo(_ model: InitialState) {
        switch model {
            case .data: state = .data
            case .rcdata: state = .rcdata
            case .rawtext: state = .rawtext
            case .scriptData: state = .scriptData
            case .plaintext: state = .plaintext
            case .cdataSection: state = .cdata
        }
    }
}
