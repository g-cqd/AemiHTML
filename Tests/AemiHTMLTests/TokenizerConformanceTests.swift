import Foundation
import Testing

@testable import AemiHTML

/// The html5lib tokenizer tests, tokens and parse error codes (`Scripts/fetch-html5lib.sh` fills the cache; without it the tests are disabled, with the reason).
@Suite(
    "The tokenizer against html5lib",
    .enabled(if: !Html5libTokenizer.files.isEmpty, "run Scripts/fetch-html5lib.sh")
)
struct TokenizerConformanceTests {
    @Test(arguments: Html5libTokenizer.files)
    func `a file of html5lib tokenizer tests gives the tokens it lists`(file: String) {
        let (cases, _) = Html5libTokenizer.cases(in: file)
        let failures = cases.compactMap { Html5libTokenizer.run($0, comparesErrors: false) }
        #expect(
            failures.isEmpty,
            Comment(
                rawValue: "\(failures.count) of \(cases.count) failed\n" + failures.prefix(6).joined(separator: "\n")
            )
        )
    }

    @Test(arguments: Html5libTokenizer.files)
    func `and the parse errors it lists`(file: String) {
        let (cases, _) = Html5libTokenizer.cases(in: file)
        let failures = cases.compactMap { Html5libTokenizer.run($0, comparesErrors: true) }
        #expect(
            failures.isEmpty,
            Comment(
                rawValue: "\(failures.count) of \(cases.count) failed\n" + failures.prefix(6).joined(separator: "\n")
            )
        )
    }
}

@Suite(
    "The tokenizer's coverage of html5lib",
    .enabled(if: !Html5libTokenizer.files.isEmpty, "run Scripts/fetch-html5lib.sh")
)
struct TokenizerCoverageTests {
    @Test func `the files hold thousands of cases and few are skipped`() {
        var total = 0
        var skipped = 0
        for file in Html5libTokenizer.files {
            let found = Html5libTokenizer.cases(in: file)
            total += found.cases.count
            skipped += found.skipped
        }
        #expect(total > 6000 && skipped < 40, "\(total) cases, \(skipped) skipped")
    }
}
