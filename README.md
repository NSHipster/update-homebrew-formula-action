# Update Homebrew Formula

Synchronizes a Homebrew formula with a GitHub release.

> 🚧 This action is still in development, and not ready for general use.

## Usage

### Inputs

- `repository`:
  The project repository (e.g. mona/hello).
  **Required.**
- `tap`:
  The Homebrew tap repository (e.g. mona/homebrew-formulae).
  **Required.**
- `formula`:
  The path to the formula in the tap repository (e.g. Formula/hello.rb).
  **Required.**

> **Important**:
> This requires the `GITHUB_TOKEN` environment variable to be set.

### Example Workflow

```yml
# .github/workflows/release.yml
name: Release

on:
  release:
    types:
      - created

jobs:
  homebrew:
    name: Update Homebrew formula
    runs-on: ubuntu-latest
    steps:
      - uses: SwiftDocOrg/update-homebrew-formula@main
        with:
          repository: mona/hello
          tap: mona/homebrew-formulae
          formula: Formula/hello.rb
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## License

MIT
