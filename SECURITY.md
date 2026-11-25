# Security Policy

## Scope

`AemiHTML` parses untrusted HTML byte streams iteratively with bounded stack depth, formatting-element caps, and total (non-throwing) error recovery. No scripts are executed and no network access is performed.

## Supported Versions

Security fixes land on `main` and the latest tagged release (when releases are published). Pin a specific tag or commit revision for reproducible builds.

## Reporting a Vulnerability

Report security issues privately via [GitHub Security Advisories](https://github.com/g-cqd/AemiHTML/security/advisories/new). Do not open public issues with exploit details or sensitive material. Include the commit or version, platform, and a minimal reproduction.

## Response targets (best-effort, solo maintainer)

This project is maintained by a single developer on a best-effort basis; the targets below are realistic guidelines
rather than contractual SLAs:

| Milestone | Best-effort target |
| --- | --- |
| Private acknowledgement | Within **7–14 days** |
| Initial triage & severity confirmation | Within **30 days** |
| Fix & advisory — **Critical** | Within **30 days** (sooner when actively exploited) |
| Fix & advisory — **High** | Within **60–90 days** |
| Fix — **Medium / Low** | Next scheduled release, as time permits |

Security fixes in released versions are published with a GitHub Security Advisory (and CVE identifier where applicable)
and named in the release notes.