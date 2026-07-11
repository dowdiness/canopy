---
name: changelog-management
description: >
  A skill for creating and maintaining a user-facing changelog. It combines
  the automation of analyzing git commits with the clear, human-readable
  structure of the "Keep a Changelog" standard and suggests the next
  semantic version number.
---

# Changelog Management

This skill provides a comprehensive approach to managing this project's
`CHANGELOG.md` file. It merges the efficiency of automated git analysis with the
high-quality formatting standards of "Keep a Changelog" and helps automate
Semantic Versioning.

## Core Principles

1.  **Follow "Keep a Changelog":** The final output *must* adhere to the
    [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) standard.
2.  **Leverage Git History:** The process begins by analyzing git commits to gather
    raw changes, saving developer time.
3.  **Human-First Output:** Technical commit messages are translated into clear,
    user-friendly notes that explain the impact to end-users.
4.  **Automate Versioning:** Based on the changes, a new Semantic Version number is
    suggested, removing the manual effort.

## When to Use This Skill

- When preparing for a new software release.
- When determining the next version number based on recent changes.
- When creating release notes from a set of commits.

## The Process

1.  **Scan Commits:** Analyze the git history between two refs (tags, branches,
    commits) or since the last release tag.
2.  **Filter Noise:** Ignore internal commits (`docs:`, `test:`, `refactor:`,
    `chore:`, etc.) that do not impact the user-facing behavior of the software.
3.  **Categorize Changes:** Group the remaining commits into one of the "Keep a
    Changelog" categories:
    - `Added` for new features. (`feat:`)
    - `Changed` for changes in existing functionality. (`change:`)
    - `Performance` for performance improvements. (`perf:`)
    - `Deprecated` for soon-to-be-removed features. (`deprecate:`)
    - `Removed` for now-removed features. (`remove:`)
    - `Fixed` for any bug fixes. (`fix:`, `bug:`)
    - `Security` in case of vulnerabilities. (`security:`)
    - Note: Breaking changes should be explicitly marked in commit footers
      (e.g., `BREAKING CHANGE: ...`) and will lead to a MAJOR version bump.
    - Note: Some `refactor:` commits may affect public APIs. If a refactor
      changes user-facing behavior or APIs, recategorize it accordingly.
4.  **Rewrite for Clarity:** Transform the technical commit messages into concise,
    human-readable descriptions.
5.  **Suggest Next Version:** Based on the highest-impact category, determine the
    next version number from the most recent git tag:
    - **MAJOR** (`x.0.0`): If any commit introduces a `BREAKING CHANGE`.
    - **MINOR** (`1.x.0`): If `Added` commits exist (new features).
    - **PATCH** (`1.2.x`): If only `Fixed`, `Security`, or other minor `Changed`
      commits exist.
6.  **Format Output:** Present the categorized notes under the suggested new
    version heading and date.
7.  **Update Package Version:** For MoonBit packages, update the `version` field
    in `moon.pkg.json` to match the new version number.

## MoonBit Package Versioning

Each MoonBit package maintains its own version and changelog:

- **Package version**: `moon.pkg.json` contains a `"version"` field
- **Package changelog**: `CHANGELOG.md` in the package directory
- **Module version**: `moon.mod.json` version is for library releases (separate concern)

When updating a package changelog:
1. Add the new version entry to `CHANGELOG.md`
2. Update `"version"` in `moon.pkg.json` to match
3. Keep module version (`moon.mod.json`) unchanged unless releasing the library

Example package structure:
```
event-graph-walker/
├── moon.mod.json        # Module version (library release)
├── rle/
│   ├── moon.pkg.json    # "version": "0.3.0"
│   └── CHANGELOG.md     # ## [0.3.0] - 2026-01-29
├── text/
│   ├── moon.pkg.json    # "version": "0.1.0"
│   └── CHANGELOG.md     # ## [0.1.0] - ...
```

## How to Use

- **Generate a changelog and get the next version:**
  `"Generate a changelog for commits since the last release and suggest the next version number."`
- **Draft an update from a specific branch:**
  `"Draft a new changelog section from the commits on 'develop' since the 1.2.0 tag and tell me what the next version should be."`
- **Include internal changes (developer-facing):**
  `"Generate a changelog including refactor and test changes for a developer release."`

## Example

**Prompt**: `"Generate a changelog from commits since v1.2.3 and suggest the next version."`

**Generated Output**:

> Based on the changes, I suggest the next version be **1.3.0**.
>
> Here is the draft for your `CHANGELOG.md`:
>
> ```markdown
> ## [1.3.0] - 2026-01-26
>
> ### Added
> - Team Workspaces: You can now create separate workspaces for different
>   projects and invite team members to collaborate.
>
> ### Fixed
> - Resolved an issue that prevented large images from uploading correctly.
> ```
