# Contributing

Issues and pull requests are welcome.

## Before you open a pull request

[Repository layout](README.md#repository-layout) in the README explains where things go.

CI runs shellcheck and the script tests on every pull request.

Keep a pull request to one change. This project keeps its dependencies few, so a new one needs a good reason in the description.

## Pull request titles

Pull requests are squash-merged, so the title becomes the commit on `main`. Titles follow [Conventional Commits](https://www.conventionalcommits.org/), and a check enforces it. Use `fix:`, `feat:`, `docs:`, `test:`, `refactor:`, `ci:` or `chore:`, with an optional scope such as `fix(bridge): …`. Mark a breaking change with `!`.

Dependabot keeps dependencies current; its minor and patch updates merge once CI passes.

## License

By contributing you agree that your contribution is licensed under the project's license, MIT ([LICENSE](LICENSE)).
