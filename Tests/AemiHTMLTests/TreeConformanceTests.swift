import Foundation
import Testing

@testable import AemiHTML

/// The html5lib tree-construction tests (the last copy html5lib held, pinned by `Scripts/fetch-html5lib.sh`), against the standard as it reads now. Where the standard has moved since, `known-differences.txt` lists the case.
@Suite("The tree builder against html5lib", .enabled(if: !Html5libTree.files.isEmpty, "run Scripts/fetch-html5lib.sh"))
struct TreeConformanceTests {
    @Test(arguments: Html5libTree.files)
    func `a file of tree-construction tests gives the trees it lists`(file: String) {
        let known = Html5libTree.knownDifferences
        let cases = Html5libTree.cases(in: file)
        var failures: [String] = []
        var fixed: [String] = []
        for test in cases {
            let result = Html5libTree.run(test)
            if known[test.id] != nil {
                if result == nil { fixed.append(test.id) }
            } else if let result {
                failures.append(result)
            }
        }
        #expect(
            failures.isEmpty,
            Comment(
                rawValue: "\(failures.count) of \(cases.count) failed\n" + failures.prefix(4).joined(separator: "\n\n")
            )
        )
        #expect(fixed.isEmpty, "these known differences pass now, take them out of known-differences.txt: \(fixed)")
    }
}

@Suite(
    "The tree-construction harness itself",
    .enabled(if: !Html5libTree.files.isEmpty, "run Scripts/fetch-html5lib.sh")
)
struct TreeHarnessTests {
    @Test func `the files hold about 1,800 cases and the dump of a small tree is the one the tests write`() {
        let total = Html5libTree.files.reduce(0) { $0 + Html5libTree.cases(in: $1).count }
        #expect(total > 1700, "\(total) cases")
        let document = HTMLParser.parse(Array("<p>One<p>Two".utf8))
        #expect(
            Html5libTree.dump(document, fragment: false)
                == "| <html>\n|   <head>\n|   <body>\n|     <p>\n|       \"One\"\n|     <p>\n|       \"Two\""
        )
    }

    @Test func `a case whose expectation is wrong is reported`() {
        let wrong = Html5libTree.Case(
            file: "x.dat",
            number: 1,
            data: "<b>x",
            fragment: nil,
            scripting: false,
            expected: "| <html>"
        )
        #expect(Html5libTree.run(wrong) != nil)
    }
}
