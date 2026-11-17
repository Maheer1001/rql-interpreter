# PLC (Stack package)

Haskell implementation of the PLC / RQL interpreter: Alex/Happy front end, resolver, Turtle support, and query evaluation.

## Layout

| Path | Role |
|------|------|
| `app/` | `plc-exe` entrypoint (`Main.hs`, CLI error formatting) |
| `src/` | Library: `Lexer.x`, `Parser.y`, `Evaluator.hs`, `Turtle/`, … |
| `data/` | Sample `.ttl` graphs and `.rql` queries (run CLI from `data/` or pass paths accordingly) |
| `test/` | `stack test` |

The VS Code grammar lives next to this folder in `../vscode-rql-syntax/`.

## Stack commands

| Typical command | With Stack |
|-----------------|------------|
| `ghci` | `stack ghci` |
| Build | `stack build` |
| Run executable | `stack exec -- plc-exe <args>` |

Locate the built binary: `stack exec -- whereis plc-exe`

## Alex and Happy

Stack runs Alex and Happy as build steps. To run them manually (for example to inspect `.info` output):

```shell
stack exec -- alex <args>
stack exec -- happy <args>
```

Remove any generated artifacts you no longer need before the next `stack build` if you generated files outside the normal build tree.

## Module names (Haskell)

Library modules under `src/` use names like `Parser`, `Lexer` (flat under `src/` as set in `package.yaml`). The executable in `app/` imports those modules directly.
