# Bash scripts

- Write all script text in English, including comments, prompts, progress output and errors.
- Keep scripts readable for humans unfamiliar with Bash: descriptive `snake_case` names, visible sequential steps, blank lines between logical steps, and small helpers for repeated or substantial operations. Prefer explicit conditionals to compact shell tricks.
- Use `#!/bin/bash` and support macOS's bundled Bash 3.2. Avoid newer features such as `mapfile` and dependencies requiring a package manager.
- Use `set -euo pipefail`, quote paths and expansions, use arrays for choices/arguments, and `read -r` for input. Handle expected failures explicitly with actionable messages. Do not use `eval` or parse JSON with text substitutions.
- Prefer a numbered terminal menu to a mandatory interactive dependency. Explain the action and its effects before asking for a selection; support cancellation and invalid input.
- Make terminal output welcoming: a short introduction, numbered stages, spaced choices, and actionable errors. Use ANSI palette colors with text/symbol labels so color never carries meaning alone. Disable styling for redirected output, `TERM=dumb`, or nonempty `NO_COLOR`. Keep URLs visible and avoid fixed-width boxes, low-contrast dim text, and animated decoration.
- Resolve paths from `BASH_SOURCE`, independent of the caller's working directory. Use `mktemp` and an EXIT trap for temporary data. Never store credentials or personal logs in the repository.
- Validate prerequisites before making changes. Preserve the user's work; never automatically stash, reset, clean, force a checkout, or force-kill an app. Explain how to recover when an operation leaves persistent state.
- Give network requests timeouts and actionable failure messages. Handle pagination when listing remote data, and avoid persisting credentials or changing the user's configuration.
- Check with `/bin/bash -n` and focused temporary fixtures or mocked commands for consequential branches. Keep checks isolated from the user's checkout, running apps and external services. Follow the repository's build requirements and describe precisely what was verified.
