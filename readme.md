# Julia REPL Tree

## Project Goals

- Index JSON Pointer paths to callable leaf providers.
- Maintain the registry as a flat dictionary keyed by JSON Pointer strings.
- Explore REPL-friendly renderings that restructure the registry for easier browsing.
- Keep each rendering approach testable as we iterate on designs.
- First rendering draft: nested NamedTuples where branch fields become ergonomic identifiers and leaf tuples retain both the original pointer and its callable value.

## Running Tests

Use `scripts/run-tests.sh` to execute the test suite with a
project-local Julia depot:

```
./scripts/run-tests.sh
```

The script keeps package downloads isolated to the repository and can be
run from any shell session without affecting global Julia configuration.
