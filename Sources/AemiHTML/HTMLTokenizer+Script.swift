internal import AemiKernel
internal import AemiKernels

/// Where the scan of script data is: whether it is inside `<!--`, inside a `<script` within that, and how many dashes just came.
struct ScriptScan {
    var escaped = false
    var doubleEscaped = false
    var dashes = 0
    var runStart: Int
}

extension HTMLTokenizer {
    /// 13.2.5.4 and 13.2.5.17 to 13.2.5.33: script data. Its text is the source, NUL as U+FFFD, up to `</script` (the last start tag's name) and whitespace, `/` or `>`; what the states in between decide is
    /// where that end tag is allowed: not inside `<!--` ... `-->` unless a `<script` has opened a second level there. Two flags and a count of dashes carry all of it.
    mutating func scriptDataState() {
        var scan = ScriptScan(runStart: pos)
        while true {
            let stop = find(scan.escaped ? Stops.scriptEscaped : Stops.scriptNormal, from: pos)
            if stop > pos { scan.dashes = 0 }
            pos = stop
            guard pos < count else {
                // Its state (the escapes, the dashes) is in this step: in a stream it is undone and run again whole.
                reachedEnd()
                emitText(scan.runStart, count)
                if scan.escaped { error(.eofInScriptHtmlCommentLikeText) }
                done = true
                return
            }
            switch Int(input[pos]) {
                case 0x00:
                    emitText(scan.runStart, pos)
                    error(.unexpectedNullCharacter)
                    emitScalars(0xFFFD)
                    pos += 1
                    scan.runStart = pos
                    scan.dashes = 0
                case 0x2D:
                    scan.dashes = Swift.min(scan.dashes + 1, 2)
                    pos += 1
                case 0x3E:
                    if scan.dashes == 2 {
                        scan.escaped = false
                        scan.doubleEscaped = false
                    }
                    scan.dashes = 0
                    pos += 1
                default:
                    scan.dashes = 0
                    if scriptLessThan(&scan) { return }
            }
        }
    }

    /// At a `<` in script data: begins the end tag if this is it (true); else moves `pos` past what it settles, or past the `<` alone.
    private mutating func scriptLessThan(_ scan: inout ScriptScan) -> Bool {
        let next = byte(pos + 1)
        if !scan.doubleEscaped, next == 0x2F, let end = appropriateEndTag(at: pos) {
            emitText(scan.runStart, pos)
            tagStart = pos
            beginTag(isEnd: true)
            setTagName(pos + 2, end)
            pos = end
            state = .beforeAttributeName
            return true
        }
        if !scan.escaped {
            if next == 0x21, byte(pos + 2) == 0x2D, byte(pos + 3) == 0x2D {
                scan.escaped = true
                scan.dashes = 2
                pos += 4
            } else {
                pos += 1
            }
            return false
        }
        // Escaped: a `<script` opens the second level, and in it a `</script` closes it.
        let wordStart = scan.doubleEscaped ? pos + 2 : pos + 1
        pos += 1
        guard scan.doubleEscaped ? next == 0x2F : Self.isAlpha(next) else { return false }
        var end = wordStart
        while Self.isAlpha(byte(end)) { end += 1 }
        let terminator = byte(end)
        if Self.isWhitespace(terminator) || terminator == 0x2F || terminator == 0x3E,
            end - wordStart == 6, matches("script", at: wordStart)
        {
            scan.doubleEscaped.toggle()
            pos = end + 1
        }
        return false
    }
}
