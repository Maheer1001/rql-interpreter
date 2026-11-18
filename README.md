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

## Test

```bash
cd plc
cabal test
```

The suite runs `t1`–`t10` and `test_order` against the expected outputs in `test/expected/`, and checks that the type-checker and parse-error cases fail as expected (17 checks). With Stack: `stack test`.

## Layout

| Path | Purpose |
|---|---|
| `plc/src/` | Library: `Lexer.x`, `Parser.y`, `Resolver.hs`, `TypeChecker.hs`, `Evaluator.hs`, and `Turtle/` (Turtle lexer, parser and normaliser) |
| `plc/app/` | `plc-exe` CLI and error formatting for parse and type errors |
| `plc/data/` | Sample graphs and queries (`part1/`, `part2/`, `extra/`) plus type-checker cases |
| `plc/test/` | Test suite (`cabal test` / `stack test`) with expected outputs |
| `vscode-rql-syntax/` | VS Code extension with a TextMate grammar for `.rql` |

See [`plc/README.md`](plc/README.md) for Stack commands and notes on Alex and Happy.

## VS Code extension

Open `vscode-rql-syntax/` in VS Code and press **F5** (Run Extension), or package it with `vsce`.
