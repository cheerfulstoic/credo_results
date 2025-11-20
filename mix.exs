defmodule CredoResults.MixProject do
  use Mix.Project

  @source_url "https://github.com/cheerfulstoic/credo_results"

  def project do
    [
      app: :credo_results,
      version: "0.1.0",
      elixir: "~> 1.15",
      description:
        "A library adding credo checks to deal with :ok/:error results (:ok, :error, {:ok, ...}, {:error, ...})",
      licenses: ["MIT"],
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs()
    ]
  end

  defp package do
    [
      maintainers: ["Brian Underwood"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      extra_section: "GUIDES",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      main: "readme"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, ">= 1.0.0"},
      {:mix_test_interactive, "~> 5.0", only: :dev, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
