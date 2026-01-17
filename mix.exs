# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Example.SO101.MixProject do
  use Mix.Project

  def project do
    [
      app: :bb_example_so101,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {BB.Example.SO101.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bb, bb_dep("~> 0.14")},
      {:bb_ik_dls, bb_dep("~> 0.3", :bb_ik_dls)},
      {:bb_liveview, bb_dep("~> 0.2", :bb_liveview)},
      {:bb_reactor, bb_dep("~> 0.2", :bb_reactor)},
      {:bb_servo_feetech, bb_dep("~> 0.2", :bb_servo_feetech)},
      {:phoenix, "~> 1.8.3"},
      {:phoenix_html, "~> 4.1"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:tidewave, "~> 0.5", only: [:dev]},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind bb_example_so101", "esbuild bb_example_so101"],
      "assets.deploy": [
        "tailwind bb_example_so101 --minify",
        "esbuild bb_example_so101 --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  defp bb_dep(default, package \\ :bb) do
    case System.get_env("BB_VERSION") do
      nil -> default
      "local" -> [path: "../#{package}", override: true]
      "main" -> [git: "https://github.com/beam-bots/#{package}.git", override: true]
      version -> "~> #{version}"
    end
  end
end
