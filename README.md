# RQL Interpreter

An interpreter for **RQL**, a SPARQL-like query language over RDF graphs written in Turtle. It's written in Haskell with an Alex lexer, a Happy parser, a resolver, a type checker, a Turtle parser and an evaluator. A VS Code extension adds syntax highlighting for `.rql` files.

> **Group project.** Built by a team for the University of Southampton *Programming Language Concepts* module (COMP2322, 2026). This repo is a snapshot of the code, which I continued to develop after the module ended.

## Example

```text
LET @baz = <baz.ttl>
LET @ont = <http://example.org/ont/>

CONSTRUCT { ?s @ont:hasAge ?age }
WHERE {
  @baz { ?s @ont:hasAge ?age }
  FILTER(?age >= 21)
}
```

`LET` binds graphs (loaded from Turtle files) and prefixes. `CONSTRUCT … WHERE` matches triple patterns and builds a new graph, and also supports `UNION` and `FILTER` with comparisons and boolean operators. The output is Turtle.

## Prerequisites

- [GHC](https://www.haskell.org/ghc/) 9.6 (tested with 9.6.7) and [cabal-install](https://www.haskell.org/cabal/) 3.x (tested with 3.12.1.0), both installable with [GHCup](https://www.haskell.org/ghcup/)
- [Alex](https://hackage.haskell.org/package/alex) and [Happy](https://hackage.haskell.org/package/happy) generate the lexers and parsers from the `.x`/`.y` files. You don't need to install them yourself: the package declares them as `build-tool-depends`, so `cabal build` fetches and builds them (tested with alex 3.5.4.2 and happy 2.2). To install them globally anyway, run `cabal install alex happy`.
- Alternatively, [Stack](https://docs.haskellstack.org/) works too (`stack.yaml` pins `lts-21.25`)

No API keys or environment variables are needed.

## Build

```bash
cd plc
cabal update
cabal build
```

With Stack: `cd plc && stack build`.

## Run

`plc-exe` takes a `.rql` file and prints the resulting graph as Turtle (N-Triples style) to stdout. Run queries from the folder that holds their `.ttl` files, because `LET @g = <file.ttl>` paths are resolved relative to the working directory:

```bash
cd plc/data/part1
cabal run -v0 plc-exe -- t2.rql
```

Output:

```text
<http://example.org/baz/alice> <http://example.org/ont/hasAge> 30 .
<http://example.org/baz/carol> <http://example.org/ont/hasAge> 21 .
<http://example.org/baz/eve> <http://example.org/ont/hasAge> 25 .
<http://example.org/baz/frank> <http://example.org/ont/hasAge> 21 .
```

With Stack: `stack exec -- plc-exe t2.rql`.

Queries in `data/extra/` that read `foo.ttl`, `baz.ttl`, `qux.ttl` or `quux.ttl` use the graphs in `data/part1/`, so run them from there (for example `cabal run -v0 plc-exe -- ../extra/t14.rql`). Queries that use `part1/...` paths (in `data/test/`) run from `data/`.

## Testing

Requirements: **GHC 9.6.x** (tested with 9.6.7) and **cabal-install 3.x** (tested with 3.12.1.0). Alex and Happy are fetched by cabal automatically. On a fresh machine run `cabal update` once before the first build.

### Quick setup check

To confirm your toolchain and everything else is wired up correctly in one go, run the setup check from the repo root:

```bash
sh scripts/setup-check.sh                                    # Linux, macOS, Git Bash
```

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-check.ps1   # Windows (or: pwsh scripts/setup-check.ps1)
```

It prints `PASS`/`FAIL` for each step and ends with `SETUP CHECK PASSED` (exit 0) or `SETUP CHECK FAILED` plus a list of what failed (exit 1). Add `--no-test-suite` (sh) or `-NoTestSuite` (PowerShell) to skip the final step.

| Step | What it proves |
|---|---|
| Toolchain | `ghc` and `cabal` are on your `PATH` and are the supported versions |
| Build | `cabal build exe:plc-exe` succeeds (dependencies, Alex and Happy all resolve) |
| Example programs | The real `plc-exe` binary, run from the right folder, prints exactly the expected Turtle for every program in [`plc/test/golden.txt`](plc/test/golden.txt) (diff shown on mismatch) |
| Error reporting | Parse, type and evaluation errors come out on stderr with the right heading and nothing on stdout |
| Test suite | `cabal test` passes |

### Test suite

```bash
cd plc
cabal test                                  # summary only
cabal test --test-show-details=direct       # one PASS/FAIL line per test
```

With Stack: `stack test`. The suite (`plc/test/Spec.hs`, 66 tests) exercises the library pipeline directly, stage by stage:

| Group | What it proves |
|---|---|
| RQL lexer | Source text becomes the right tokens (graph files vs URIs, variables, literals, multi-word keywords, operators, comments, error tokens for unknown characters) |
| Turtle front end | `.ttl` files parse and normalise correctly: `@base` and `@prefix`, `;` and `,` lists, comments, duplicate triples removed, syntax errors and relative prefix URIs rejected |
| Example programs | Every query in `plc/test/golden.txt` (`t1`–`t16`, `test_order`, `test_orderBy`, `test_regex`) produces the output in `plc/test/expected/` |
| Query constructs | One small program per language feature (the example programs add `UNION`, `COUNT`, `LAST`, `IF … THEN … ELSE`, `REGEX` and `TYPE(…) = URI`): pattern matching with prefixes, literals and `_`, `INTERSECT`/`EXCEPT`/`OPTIONAL`, `FILTER` with `&&`, `\|\|`, `!`, arithmetic and `ABS`, string and URI comparison, `TYPE`, `GROUP BY` + `HAVING` with `SUM`/`MIN`/`MAX`/`AVG`, `ORDER BY`, `FIRST`, `DISTINCT`, multiple queries per program |
| Error paths | Lexical, parse, type, resolution (undefined graph), missing-file and evaluation errors are each reported as that kind of error; valid type-checker cases pass |

### Adding a test

- **New example program:** add the `.rql` (and any `.ttl`) under `plc/data/`, save the expected output as `plc/test/expected/<name>.out`, and add a line `<run dir> <query> <expected>` to `plc/test/golden.txt`. Both `cabal test` and the setup check pick it up.
- **New construct or error case:** add an entry to `constructTests` or `errorTests` in `plc/test/Spec.hs`.

Note: `plc-exe` exits with status 0 even when it reports an error, so scripts should check stderr rather than the exit code (the setup check does this).

## Layout

| Path | Purpose |
|---|---|
| `plc/src/` | Library: `Lexer.x`, `Parser.y`, `Resolver.hs`, `TypeChecker.hs`, `Evaluator.hs`, and `Turtle/` (Turtle lexer, parser and normaliser) |
| `plc/app/` | `plc-exe` CLI and error formatting for parse and type errors |
| `plc/data/` | Sample graphs and queries (`part1/`, `part2/`, `extra/`) plus type-checker cases |
| `plc/test/` | Test suite (`cabal test` / `stack test`), `golden.txt` manifest and expected outputs |
| `scripts/` | `setup-check.sh` / `setup-check.ps1`: toolchain, build and end-to-end check |
| `vscode-rql-syntax/` | VS Code extension with a TextMate grammar for `.rql` |

See [`plc/README.md`](plc/README.md) for Stack commands and notes on Alex and Happy.

## VS Code extension

Open `vscode-rql-syntax/` in VS Code and press **F5** (Run Extension), or package it with `vsce`.
