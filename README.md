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

## Build and run

Requires [Stack](https://docs.haskellstack.org/).

```bash
cd plc
stack build
stack test

cd data/part1
stack exec -- plc-exe t2.rql
```

Run queries from the folder that holds their `.ttl` files, because `LET @g = <file.ttl>` paths are resolved relative to the working directory.

## Layout

| Path | Purpose |
|---|---|
| `plc/src/` | Library: `Lexer.x`, `Parser.y`, `Resolver.hs`, `TypeChecker.hs`, `Evaluator.hs`, and `Turtle/` (Turtle lexer, parser and normaliser) |
| `plc/app/` | `plc-exe` CLI and error formatting for parse and type errors |
| `plc/data/` | Sample graphs and queries (`part1/`, `part2/`, `extra/`) plus type-checker cases |
| `plc/test/` | `stack test` suite with expected outputs |
| `vscode-rql-syntax/` | VS Code extension with a TextMate grammar for `.rql` |

See [`plc/README.md`](plc/README.md) for more Stack commands and notes on Alex and Happy.

## VS Code extension

Open `vscode-rql-syntax/` in VS Code and press **F5** (Run Extension), or package it with `vsce`.
