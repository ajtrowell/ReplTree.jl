# Julia REPL Tree

## Project Goals

- Index JSON Pointer paths to callable leaf providers.
- Maintain the registry as a flat dictionary keyed by JSON Pointer strings.
- Explore REPL-friendly renderings that restructure the registry for easier browsing.
- Keep each rendering approach testable as we iterate on designs.
- First rendering draft: nested NamedTuples where branch fields become ergonomic identifiers and leaf tuples retain both the original pointer and its callable value.
- Second rendering draft: `MenuBranch` hierarchy exposing raw leaf values with tab-friendly property access, callable leaves (invoked via `()`), custom display showing branch choices and invokable endpoints, and support for reference-style data alongside closures.
- Provide concrete registries for cats, kitchens (mutable stove state), dishwashers (queue + cycles), and a combined kitchen registry composed via branch-aware merging utilities.

## Registry Utilities

- `merge_registry` / `merge_registry!` merge a registry of leaves into an existing registry under a JSON Pointer branch while preventing conflicts with existing leaves.
- Registries can contain callables, mutable configuration structs, or other reference data for REPL exploration.

## Example Registries

- `example_cat_registry()` – basic callable leaves only.
- `example_kitchen_registry()` – mix of closures and mutable stove configuration.
- `example_dishwasher_registry()` – dishwasher controller with queue and cycle management.
- `example_kitchen_combo_registry()` – kitchen registry with the dishwasher merged under `/appliances/dishwasher`.

## Running Tests

Use `scripts/run-tests.sh` to execute the test suite with a
project-local Julia depot:

```
./scripts/run-tests.sh
```

The script keeps package downloads isolated to the repository and can be
run from any shell session without affecting global Julia configuration.
