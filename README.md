# RQL Interpreter

An interpreter for **RQL**, a small query language over RDF/Turtle graphs. It's written in Haskell with an Alex lexer, a Happy parser, a resolver and type checker, a Turtle parser and an evaluator. A VS Code extension adds syntax highlighting for `.rql` files.

> **Group project.** Built by a team for the University of Southampton *Programming Language Concepts* module (COMP2322, 2026). This repo is a snapshot of the code, which I continued to develop after the module ended.

## About this repo

RQL interpreter (Haskell / Stack) plus a small VS Code grammar extension. Human-authored files in this repo use **kebab-case** names for multi-word Markdown, sample data, and editor assets (for example `docs/git-basics.md`). Haskell module names stay **PascalCase** as required by the language.

## Repository layout

| Path | Purpose |
|------|---------|
| `plc/` | Stack project: lexer, parser, evaluator, CLI (`plc-exe`) |
| `vscode-rql-syntax/` | VS Code extension: TextMate grammar for `.rql` |
| `docs/git-basics.md` | Team Git workflow reference |

## Build and run (interpreter)

Build from the Stack project root; run sample queries from `plc/data` so `LET … = <file.ttl>` resolves next to the query.

```shell
cd plc/data
stack build
stack exec -- plc-exe t2.rql
```

## Project structure (interpreter)

```
plc/
├── package.yaml          # Hpack / Stack package definition
├── stack.yaml
├── app/                  # Executable (CLI, I/O)
├── src/                  # Library (Alex / Happy, evaluator, …)
├── data/                 # Sample Turtle graphs and RQL queries
└── test/
```

See `plc/README.md` for Stack commands, Alex/Happy notes, and module layout.

## VS Code extension

Open `vscode-rql-syntax/` in VS Code and use **Run Extension** (F5), or package with `vsce` when you are ready to publish. The published extension id comes from `package.json` `name` (`vscode-rql-syntax`); the grammar `language` id remains `rql` for `.rql` files.

## Documentation

- [docs/git-basics.md](docs/git-basics.md) — Git commands and workflow for the course repo.
