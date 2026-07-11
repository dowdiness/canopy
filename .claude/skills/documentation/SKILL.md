# Documentation Skill

**Skill:** Token-efficient, well-organized documentation following a clear rule-based hierarchy

**Invoke with:** `/documentation` or when user asks to create/update documentation

## Purpose

Maintain consistent, token-efficient documentation across the project using a hierarchical organization that minimizes redundancy and maximizes clarity.

## Documentation Hierarchy Rules

### 1. CLAUDE.md (Quick Reference Only)

**Purpose:** Entry point for Claude Code - minimal, essential information only

**Max length:** ~100 lines

**Contains:**
- Project name and brief description
- Module structure (one-liner per module)
- Quick commands (build, test, format)
- Links to detailed docs
- Key facts (technology, test count, LOC)
- Important notes (max 5 bullet points)

**Does NOT contain:**
- Detailed explanations
- Architecture details
- Long code examples
- Step-by-step guides
- Historical information

**Template:**
```markdown
# Claude Code Quick Reference

Project Name - Brief description

## Project Structure
[List modules with one-line descriptions]

## Quick Commands
[Only most common commands]

## Documentation
[Links to docs/ subdirectories]

## Key Facts
[5-10 bullet points max]

## Important Notes
[Critical warnings/conventions only]
```

### 2. docs/ Directory Structure

**Rule:** Organize by CATEGORY, not by file purpose

#### docs/architecture/
**Purpose:** System design and CRDT implementation details

**Contains:**
- Module structure and relationships
- Algorithm implementations (eg-walker, FugueMax, etc.)
- Network protocols and synchronization
- Data structures and their relationships

**File naming:** `topic.md` (e.g., `modules.md`, `network-sync.md`)

**Include README.md** with category overview and links

#### docs/development/
**Purpose:** Guides for developers working on the project

**Contains:**
- Development workflow (build, test, commit, PR)
- Coding conventions and standards
- Testing guidelines
- Debugging guides

**File naming:** `topic.md` (e.g., `workflow.md`, `conventions.md`)

**Include README.md** with category overview

#### docs/performance/
**Purpose:** Benchmarking and optimization documentation

**Contains:**
- Benchmark results and analysis
- Performance optimization guides
- Profiling instructions
- Comparison data

**File naming:** `BENCHMARKS.md` (uppercase for main file), `topic.md` for others

**Consolidate:** Multiple performance docs should be merged into single source of truth

#### docs/archive/
**Purpose:** Historical documentation and completed investigations

**Contains:**
- Old investigation reports
- Completed plans (after implementation)
- Deprecated documentation
- Historical decisions

**Subdirectories:**
- `investigations/` - Research and problem-solving docs
- Old plan files (e.g., `EG_WALKER_PLAN.md`)

**Rule:** Archive, don't delete - history is valuable but shouldn't clutter main docs

### 3. Module-Level Documentation

#### Module README.md
**Purpose:** Complete reference for a specific module

**Location:** Module root (e.g., `event-graph-walker/README.md`)

**Length:** Can be longer (200-300 lines) as it's module-specific

**Contains:**
- Module overview and purpose
- Architecture specific to module
- API documentation
- Usage examples
- Key concepts
- Testing instructions
- References

**Does NOT duplicate:** General project info (keep in main CLAUDE.md/README.md)

### 4. Package-Level Documentation

#### Package README.md (Optional)
**Purpose:** Detailed documentation for complex packages

**Location:** Package directory (e.g., `parser/README.md`)

**When to create:**
- Package is complex enough to need dedicated docs
- Package might be used independently
- Package has unique concepts/terminology

**Contains:**
- Package-specific architecture
- API reference
- Examples
- Implementation notes

### 5. Root README.md

**Purpose:** User-facing project overview (for GitHub, documentation sites)

**Length:** Medium (100-150 lines)

**Contains:**
- Project description and goals
- Features
- Quick start guide
- Installation instructions
- Basic usage examples
- Links to detailed documentation
- Contributing guidelines
- License

**Audience:** External users and contributors (different from CLAUDE.md which is for Claude Code)

## Token Efficiency Principles

### 1. Single Source of Truth

**Rule:** Every piece of information has exactly ONE canonical location

**Bad Example:**
```
CLAUDE.md: Contains full architecture explanation
docs/architecture/modules.md: Duplicates same explanation
README.md: Repeats architecture info again
```

**Good Example:**
```
CLAUDE.md: "See docs/architecture/modules.md"
docs/architecture/modules.md: Full explanation (canonical)
README.md: Brief summary + link to docs/architecture/
```

### 2. Lazy Loading via Links

**Rule:** CLAUDE.md links to docs, doesn't embed them

**Implementation:**
- CLAUDE.md: `[Architecture](docs/architecture/)`
- Load detailed docs only when needed
- Reduces context window usage by 70-90%

### 3. Hierarchical Organization

**Rule:** General → Specific, Quick → Detailed

**Hierarchy:**
```
CLAUDE.md (quick reference)
  ↓ link
docs/category/ (category overview)
  ↓ link
docs/category/topic.md (detailed)
  ↓ link
module/README.md (module-specific)
```

### 4. No Duplication Across Categories

**Rule:** If information fits multiple categories, choose ONE and link from others

**Example:**
- Testing workflows → `docs/development/workflow.md`
- Testing conventions → `docs/development/testing.md`
- Don't duplicate testing info in both files - cross-reference instead

### 5. Archive Old Work

**Rule:** Don't delete historical docs, move to `docs/archive/`

**When to archive:**
- Investigation completed
- Plan implemented
- Feature redesigned
- Document superseded

**Benefits:**
- Clean root directory
- Preserve context for future
- Clear separation: active vs historical

## Documentation Workflow

### Creating New Documentation

1. **Determine category:** architecture / development / performance / archive
2. **Check for existing:** Avoid duplication
3. **Choose location:**
   - If quick reference → Add to CLAUDE.md with link to detailed doc
   - If detailed → Create in appropriate docs/ subdirectory
   - If module-specific → Module README.md
4. **Create file:** Use category-appropriate naming
5. **Update index:** Add link to parent README.md
6. **Update CLAUDE.md:** Add link if essential (but keep CLAUDE.md minimal)

### Updating Existing Documentation

1. **Find canonical location:** Use search to locate the ONE source of truth
2. **Update in place:** Never copy-paste to create duplicates
3. **Check links:** Ensure other docs linking to it are still valid
4. **Archive if obsolete:** Move to docs/archive/ instead of deleting

### Consolidating Duplicate Documentation

1. **Identify duplicates:** Multiple files covering same topic
2. **Choose canonical:** Pick best location using hierarchy rules
3. **Merge content:** Combine into single file
4. **Update links:** Point references to canonical location
5. **Archive old:** Move superseded files to docs/archive/
6. **Document consolidation:** Note in git commit message

## Examples

### Good Documentation Structure

```
crdt/
├── CLAUDE.md (96 lines)
│   Quick commands + links to docs/
│
├── README.md (117 lines)
│   User-facing overview
│
├── docs/
│   ├── README.md (index)
│   ├── architecture/
│   │   ├── README.md
│   │   ├── modules.md (CANONICAL for module info)
│   │   └── network-sync.md (CANONICAL for network info)
│   ├── development/
│   │   ├── README.md
│   │   ├── workflow.md (CANONICAL for dev process)
│   │   └── testing.md (CANONICAL for test guidelines)
│   └── performance/
│       └── BENCHMARKS.md (CANONICAL, merged 3 files)
│
└── event-graph-walker/
    └── README.md (module docs, 279 lines - OK for module level)
```

### Bad Documentation Structure

```
crdt/
├── CLAUDE.md (348 lines) ❌ Too long
│   Contains full architecture, workflows, everything
│
├── BENCHMARKS.md (500 lines)
├── PERFORMANCE.md (400 lines) ❌ Duplication
├── PERF_RESULTS.md (300 lines) ❌ Duplication
│
├── INVESTIGATION1.md ❌ Clutter
├── INVESTIGATION2.md ❌ Clutter
├── OLD_PLAN.md ❌ Clutter
│
└── No organized docs/ directory ❌ No hierarchy
```

### Good vs Bad - CLAUDE.md

**Bad (too detailed):**
```markdown
# CLAUDE.md

## Architecture

The codebase is organized into packages with the following structure:
[50 lines of package descriptions]

The causal graph uses a directed acyclic graph (DAG) to track...
[100 lines of algorithm details]

### Version Vectors
Version vectors provide compact frontier representation...
[50 lines of implementation details]
```

**Good (minimal with links):**
```markdown
# Claude Code Quick Reference

## Project Structure
- `event-graph-walker/` - CRDT library
- `crdt/` - Lambda calculus editor

**Full details:** [docs/architecture/modules.md](docs/architecture/modules.md)

## Key Facts
- Tests: 329 (103 + 226)
- CRDT: eg-walker with FugueMax
```

## Checklist for New Documentation

Before creating or updating documentation, verify:

- [ ] Information doesn't already exist elsewhere (check for duplicates)
- [ ] Correct category chosen (architecture/development/performance/archive)
- [ ] File placed in appropriate directory
- [ ] CLAUDE.md remains under 100 lines
- [ ] Links used instead of embedding content
- [ ] README.md updated in parent directory
- [ ] No duplication across files
- [ ] Historical docs moved to archive/ instead of deleted
- [ ] Single source of truth maintained

## When to Use This Skill

Invoke this skill (`/documentation`) when:

1. User asks to create or update documentation
2. User mentions docs are messy or unorganized
3. User requests documentation reorganization
4. Adding new features that need documentation
5. CLAUDE.md grows too large
6. Multiple docs cover the same topic
7. User asks "where should I document X?"

## Output Format

When using this skill, provide:

1. **Location:** Where the documentation should go
2. **Reasoning:** Why this location (cite hierarchy rules)
3. **Template:** Appropriate template for the doc type
4. **Links:** What needs to be updated in CLAUDE.md or parent README
5. **Consolidation:** If consolidating, explain what's being merged

Example:
```
Location: docs/architecture/new-feature.md
Reasoning: Architecture documentation goes in docs/architecture/
Template: [Provide architecture doc template]
Links to update:
  - docs/architecture/README.md (add link)
  - CLAUDE.md (optional, only if critical)
```

## Principles Summary

1. **CLAUDE.md = 100 lines max** - Quick reference only
2. **Single Source of Truth** - No duplication
3. **Hierarchical** - General → Specific
4. **Lazy Loading** - Link don't embed
5. **Archive, Don't Delete** - Preserve history
6. **Category-Based** - architecture/development/performance/archive
7. **Index Everything** - README.md in each directory
8. **Token Efficient** - Minimize context usage

## References

- Project documentation: [docs/README.md](../../../docs/README.md)
- Architecture docs: [docs/architecture/](../../../docs/architecture/)
- Development docs: [docs/development/](../../../docs/development/)
