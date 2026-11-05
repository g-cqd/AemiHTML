/// What an extraction produces and how (the contract of ADHTML's `HTMLDocument.extract`, rebuilt on the arena).
public struct HTMLExtractOptions: Sendable {
    public init() {}

    public enum Format: Sendable {
        /// Markdown that AemiMarkdown reads back to the structure the page had: headings, lists (nested), tables, fenced code with its language, quotes, emphasis, links, images.
        case markdown
        /// Text: blocks as paragraphs, list items on lines with their markers, nothing escaped.
        case plainText
    }

    public enum Images: Sendable {
        /// `![alt](src)`.
        case markdown
        /// The alternative text alone.
        case altText
        case drop
    }

    public var format = Format.markdown
    public var images = Images.markdown
    /// An explicit content container (`tag`, `.class` or `#id`); without one: `main`, `article`, `[role=main]`, `.content`, `#content`, `#contents`, else `body`.
    public var containerSelector: String?
    /// Rewrites each link's destination as written: return the new destination, or nil to keep the text and drop the link. Applied before the scheme check, which keeps only http, https, mailto, tel, fragments and relative references.
    public var linkResolver: (@Sendable (String) -> String?)?
    /// Cut the content into sections at `h2` (`h3` if there is none).
    public var splitsSections = true
    /// Leave out what a reader cannot see: `hidden`, `aria-hidden`, inline `display:none` and `visibility:hidden`, `type=hidden` inputs. The text of a fetched page is read by a model; hidden text is where a page puts instructions for it.
    public var dropsHiddenContent = true
    /// Parse `noscript` as markup, as a browser with scripting off does (its content is then in the page, and dropped like chrome).
    public var scripting = false
}

/// One heading and what follows it.
public struct HTMLSection: Sendable, Equatable {
    public let heading: String?
    public let content: String

    public init(heading: String?, content: String) {
        self.heading = heading
        self.content = content
    }
}

/// The result of `HTMLExtractor.extract`.
public struct HTMLExtractedPage: Sendable, Equatable {
    public let title: String?
    public let description: String?
    public let sections: [HTMLSection]

    public init(title: String?, description: String?, sections: [HTMLSection]) {
        self.title = title
        self.description = description
        self.sections = sections
    }
}
