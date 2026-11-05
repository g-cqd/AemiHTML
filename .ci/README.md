# CI

`.github/workflows/ci.yml` calls the family's pinned swift-ci workflow, configured by `action.json`; run the same
checks here with `.ci/swift-ci local`.

Each change runs quality (swift-format, SwiftLint metrics, the analyzers over `Sources`, `Tests` and
`Plugins/GenerateEntities/Sources`, and the shipped-library discipline over `Sources/AemiMarkdown`), the Linux tests
(debug, release, AddressSanitizer, a consumer build) and the macOS debug tests followed by the TLA+ models
(`Scripts/tlc.sh`: each model passes and each `.buggy.cfg` fails). The release tests carry the allocation ceilings and
the spec ratchet; the other sanitizers and macOS release run nightly or manually.

Benchmarks/ is a separate package and stays out of the analyzers: the Benchmark plugin finds its `benchmarks` global
by name, which no syntax-level analyzer can see.
