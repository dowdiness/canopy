---
summary: "moon prove requires Why3 1.7.2 + z3 4.13.x; specific version constraints, PATH setup, and symlink workaround for moonc's hardcoded Why3 paths"
created: 2026-04-12
status: resolved
tags: [moon-prove, why3, z3, toolchain]
related: [lib/semantic/proof/, docs/development/formal-verification.md]
---

# moon prove Toolchain Setup

## Version constraints

- **Why3 1.7.2** — moonc's harness expects this version. Why3 1.8.2 has different detection data and doesn't work.
- **z3 4.13.x** — Why3 1.7.2's provers-detection-data only recognizes z3 up to 4.13.x. z3 4.16.0 is "not recognized".
- **moonc 0.1.20260409** — earlier versions (0.1.20260403) had hardcoded paths to `/root/.opam/idea-dev/share/why3/`; 0.1.20260409 looks for `why3` on PATH.

## Install commands

```bash
# Install opam + Why3 + z3
opam install why3.1.7.2 --yes
pip3 install --user z3-solver==4.13.4.0

# Register z3 with Why3
why3 config detect

# Run proofs (from proof package directory)
eval $(opam env)
moon prove
```

## PATH requirement

`moon prove` requires `why3` on PATH. Use `eval $(opam env)` or `PATH="$HOME/.opam/default/bin:$PATH"`.

## Symlink workaround (moonc < 0.1.20260409)

Older moonc versions have Why3 data paths hardcoded to `/root/.opam/idea-dev/share/why3/`. Fix:

```bash
sudo chmod a+x /root
sudo mkdir -p /root/.opam/idea-dev/{share,lib}
sudo ln -s $HOME/.opam/default/share/why3 /root/.opam/idea-dev/share/why3
sudo ln -s $HOME/.opam/default/lib/why3 /root/.opam/idea-dev/lib/why3
```

Not needed with moonc 0.1.20260409+.
