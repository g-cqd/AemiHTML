# AemiHTML

WHATWG HTML5 parser, streaming tokenizer, WHATWG Encoding Standard decoders, and HTML-to-Markdown/text extractors for Swift 6. Operates in one pass over UTF-8 bytes into a flat arena document with no recursion and bounded resource limits.

```swift
import AemiHTML

let document = HTMLParser.parse(Array("<p>One<p>Two".utf8))
for node in document.descendants(of: document.root) where document.kind(node) == .element {
    print(String(decoding: document.name(node), as: UTF8.self))
}
```

Streaming and encoding-aware parsing:

```swift
let page = HTMLParser.parse(encoded: bytes, transportEncoding: "iso-8859-2")

var parser = HTMLStreamParser()
for chunk in chunks {
    parser.feed(chunk)
}
let streamed = parser.finish()
```

## Requirements

- Swift 6.4+ (Swift 6 language mode)
- macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+, or Linux

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/AemiHTML.git", branch: "main")
]
```

## Documentation

- [Architecture Decisions](docs/adr/)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

[MIT](LICENSE)
