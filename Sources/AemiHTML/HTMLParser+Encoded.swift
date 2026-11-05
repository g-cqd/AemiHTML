extension HTMLParser {
    /// Parses a document from the bytes of a file or a response, in whatever encoding it is in: the encoding is found by the standard's sniffing (a byte order mark, then `transportEncoding`, then a prescan for a `meta`, then UTF-8 or windows-1252 by the bytes),
    /// the bytes are decoded to UTF-8, and the result is parsed. `HTMLDocument.encoding` says which was used.
    ///
    /// If the encoding was only guessed and the `meta` that declares another comes after the first 1024 bytes, the parse sees it (13.2.3.5, "change the encoding") and the document is decoded again with the declared one and parsed again, once.
    ///
    /// ```swift
    /// let document = HTMLParser.parse(encoded: bytes, transportEncoding: "iso-8859-2")
    /// ```
    /// - Parameters:
    ///   - input: the bytes of the document, in any encoding.
    ///   - transportEncoding: the `charset` the transport layer gave (an HTTP `Content-Type`), if any.
    ///   - fallbackIsUTF8: with no declaration, take the bytes for UTF-8 if they are (else windows-1252); with `false`, always windows-1252.
    ///   - options: as for `parse(_:options:)`.
    /// - Returns: the document, with `encoding` set.
    public static func parse(
        encoded input: [UInt8],
        transportEncoding: String? = nil,
        fallbackIsUTF8: Bool = true,
        options: Options = Options()
    ) -> HTMLDocument {
        let sniffed = HTMLEncodingSniffer.sniff(
            input,
            transportLabel: transportEncoding,
            fallbackIsUTF8: fallbackIsUTF8
        )
        var encoding = sniffed.encoding
        var document = parse(decoding: input, as: encoding, skipping: sniffed.byteOrderMarkLength, options: options)
        if sniffed.confidence == .tentative, let declared = document.declaredEncoding, declared != encoding {
            encoding = declared
            document = parse(decoding: input, as: encoding, skipping: 0, options: options)
        }
        document.encoding = encoding
        return document
    }

    private static func parse(decoding input: [UInt8], as encoding: HTMLEncoding, skipping: Int, options: Options)
        -> HTMLDocument
    {
        if encoding == .utf8 {
            return parse(skipping > 0 ? Array(input[skipping...]) : input, options: options)
        }
        return parse(HTMLDecoder.decode(input[skipping...], as: encoding), options: options)
    }
}
