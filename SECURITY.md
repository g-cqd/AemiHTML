# Security Policy

## Scope

`AemiHTML` parses untrusted HTML byte streams iteratively with bounded stack depth, formatting-element caps, and total (non-throwing) error recovery. No scripts are executed and no network access is performed.

## Supported Versions

Security fixes land on `main` and the latest tagged release (when releases are published). Pin a specific tag or commit revision for reproducible builds.

## Reporting a Vulnerability

Report security issues privately via [GitHub Security Advisories](https://github.com/g-cqd/AemiHTML/security/advisories/new). Do not open public issues with exploit details or sensitive material. Include the commit or version, platform, and a minimal reproduction.
