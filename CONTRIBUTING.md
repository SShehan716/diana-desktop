# Contributing to Diana

Thanks for your interest in Diana. Contributions are welcome through pull requests.

## How to contribute

1. Fork this repository and create a branch from `main`.
2. Make your change. Follow the existing style: four-space indentation and the committed `.swift-format` configuration.
3. Run the checks before opening a pull request:

   ```sh
   swift test
   xcrun swift-format lint --strict --recursive Sources Tests Package.swift scripts/create-icon.swift
   ```

4. Open a pull request against `main` describing what changed and why.

For larger changes, open an issue first so the approach can be agreed before you invest time.

## License of contributions

Diana is licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE). You may use, fork, and modify it for noncommercial purposes only. Selling Diana, or any fork or derivative of it, or using it for commercial purposes is not permitted.

By submitting a contribution, you confirm that you wrote it or otherwise have the right to submit it, and you agree that:

- your contribution is licensed to everyone under the same PolyForm Noncommercial License 1.0.0; and
- you grant the project owner, Sachin Shehan, a perpetual, worldwide, irrevocable, royalty-free license to use, modify, sublicense, and relicense your contribution, including for commercial purposes.

Do not submit code, models, textures, animations, or other assets that you do not have the rights to contribute.
