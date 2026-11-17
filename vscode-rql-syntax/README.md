# RQL syntax (VS Code)

VS Code language support for **RQL** (`.rql`) using a TextMate grammar.

## Contents

- `syntaxes/rql.tmLanguage.json` — grammar (tokenization)
- `language-configuration.json` — comments, brackets, etc.
- `package.json` — extension manifest (`name`: `vscode-rql-syntax`)

## Development

Open this folder in VS Code and press **F5** to launch an Extension Development Host with the grammar loaded.

## Packaging

Use [vsce](https://github.com/microsoft/vscode-vsce) from this directory when you are ready to build a `.vsix` or publish.
