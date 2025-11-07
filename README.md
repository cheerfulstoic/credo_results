# `credo_results`

A library adding credo checks to deal with :ok/:error results (`:ok`, `:error`, `{:ok, ...}`, `{:error, ...}`)

Currently there are two different checks implemented:

`CredoResults.ConsistentResultCheck`

This rule works under the assumption that a function should either always return an :ok/:error result, or never return an :ok/:error result. This is because a function either has the possibility of failure (meaning the caller will need to deal with it) or it doesn't.  If a function has the possibility of failure, it should always be clear if it's succeeding (an :ok result) or failing (an :error result)

Some examples that would be flagged by this check:

* A function sometimes returns an integer and sometimes returns `:error` (whereas it would be better to return `{:ok, integer()}`)
* A function sometimes returns `{:ok, String.t()}` and sometimes returns `nil` (whereas it would be better to return `:error` instead of `nil`)
* A function sometimes returns `{:ok, map()}` and sometimes returns `:not_found` (whereas it would be better to return `{:error, :not_found}` instead of `:not_found`)

`CredoResults.TwoElementCheck`

This simply checks for any usage in your project of `{:ok, ...}` or `{:error, ...}` tuples which have three elements or more (a three elements tuple being the :ok/:error atom plus two values).

The idea here is that you should avoid using tuples larger than two elements because :ok/:error tuples are returned up a stack and get combined with other :ok/:error results, and having multiple patterns to match is painful.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `credo_result_types` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:credo_result_types, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/credo_result_types>.
