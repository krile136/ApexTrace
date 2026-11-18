# ApexTrace

**A lightweight execution flow tracing framework for Salesforce Apex that combines logging and test assertion capabilities.**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Coverage](https://img.shields.io/badge/Coverage-98%25-brightgreen.svg)](#test-coverage)

📚 **Documentation: [krileworks.com](https://krileworks.com/apex-stem/docs/apex-trace-guide)** — guides, API reference, and design deep-dives all live there.
(日本語ドキュメント: [https://krileworks.com/ja/apex-stem/docs/apex-trace-guide](https://krileworks.com/ja/apex-stem/docs/apex-trace-guide))

ApexTrace is part of [**Apex Stem**](https://krileworks.com/apex-stem), a set of independent, dependency-free Salesforce Apex frameworks.

## Installation

### A) Unlocked Package (recommended)

```bash
sf package install -p 04tgK000000b1ZpQAI -o <your-org> -w 10
```

Or install from the browser:

- Production / Developer Edition: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tgK000000b1ZpQAI`
- Sandbox: `https://test.salesforce.com/packaging/installPackage.apexp?p0=04tgK000000b1ZpQAI`

Current version: **v1.6.1** (`04tgK000000b1ZpQAI`). Install IDs for every release are listed on the [Releases](https://github.com/krile136/ApexTrace/releases) page.

Why the package: tests inside an installed unlocked package are **excluded from `RunLocalTests`**, and its code is **excluded from your org's coverage calculation** — your deploys stay fast and unaffected by this framework's test suite.

### B) Git Submodule

```bash
git submodule add https://github.com/krile136/ApexTrace.git force-app/main/default/classes/ApexTrace
git submodule update --init --recursive
```

`sf project deploy start -d force-app/main/default/classes/ApexTrace` deploys it like any source folder. A Makefile is also included for direct installs (`make install`).

## AI agents

This repository ships agent skills and a rule for [Claude Code](https://claude.com/claude-code) under `.claude/`:

| Path | Purpose |
|---|---|
| `.claude/rules/apex-trace.md` | Short rules applied to `*.cls` and `*.trigger` files: keep the started `Trace` instance, close it on every path, assert the path and usage in tests, write test descriptions in the project's language |
| `.claude/skills/apex-trace-logging/` | `Trace` in production code: `start` / `log` / `finish` / `skip` / `abort`, nesting, Strict and Relaxed modes, the debug log format |
| `.claude/skills/apex-trace-testing/` | `TraceFlow` path checks, `discardArrange()`, `TraceUsage` assertions with `usageOf`, bulk tests |

The skills describe the version of the tag they come from. After you upgrade ApexTrace, update the skills from the matching tag too.

### Git submodule or clone

The files are already in your project inside the ApexTrace folder. Claude Code picks them up once it reads a file in that folder. Nothing to copy.

### Unlocked package

The package installs only Apex classes. Copy the skills and the rule from the git tag that matches your installed version (replace `v1.6.1` with it):

```bash
rm -rf /tmp/apex-trace
git clone --depth 1 --branch v1.6.1 https://github.com/krile136/ApexTrace.git /tmp/apex-trace
mkdir -p .claude/skills .claude/rules
cp -r /tmp/apex-trace/.claude/skills/* .claude/skills/
cp /tmp/apex-trace/.claude/rules/apex-trace.md .claude/rules/
```

Run it from your project root. It overwrites earlier copies of these skills and leaves your other skills alone.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
