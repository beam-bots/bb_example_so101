# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

[
  tools: [
    {:credo, "mix credo --strict"},
    # `mix gettext.extract` force-recompiles the project, which empties
    # `_build/<env>/lib/<app>/ebin` and `.../consolidated` for a second or two.
    # Anything reading those beams at that moment sees nothing: dialyzer in
    # particular halts with "No .beam files to analyze". Running gettext after
    # dialyzer rather than alongside it keeps them out of each other's way.
    {:gettext, deps: [:ex_unit, :dialyzer]},
    {:reuse,
     command: ["pipx", "run", "--spec", "reuse[charset-normalizer]", "reuse", "lint", "-q"]}
  ]
]
