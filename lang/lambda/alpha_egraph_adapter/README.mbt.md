# Lambda alpha egraph adapter

This package is a **Canopy adapter** between the Lambda alpha core and the
shared `dowdiness/egraph` engine. It intentionally lives in Canopy rather than
inside `dowdiness/egraph` because its boundary types are Canopy-specific:

- `lang/lambda/alpha.AlphaTerm`, `BinderId`, and `AlphaRef`
- `lang/lambda/scope.ScopeGraph`
- `core.ProjNode[@ast.Term]`
- the named Lambda `@ast.Term` source/projection boundary

Generic egraph improvements should still go to `dowdiness/egraph` when they do
not depend on these Canopy Lambda types. This package only supplies the
Lambda-specific lowering/optimization/reification adapter and keeps parser or
projection helpers out of production imports.
