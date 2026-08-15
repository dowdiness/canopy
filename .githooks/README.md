# Legacy Git Hooks

This directory is retained only for existing checkouts. New checkouts should
use Lefthook, but an existing `core.hooksPath=.githooks` checkout delegates to
the same Lefthook hooks rather than running a separate check set. The legacy
pre-push shim forwards Git's remote arguments and ref-update stdin unchanged.

Install the current hook from the repository root with:

```bash
just install-hooks
```
