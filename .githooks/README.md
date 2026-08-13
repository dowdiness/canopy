# Legacy Git Hooks

This directory is retained only for existing checkouts. New checkouts should
use Lefthook, but an existing `core.hooksPath=.githooks` checkout delegates to
the same `just pre-commit` gate rather than running a separate check set.

Install the current hook from the repository root with:

```bash
just install-hooks
```
