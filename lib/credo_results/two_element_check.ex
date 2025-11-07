defmodule CredoResults.TwoElementCheck do
  @moduledoc """
  A custom Credo check that flags any usage of 3+ element `:ok` or `:error` tuples.

  This check enforces a strict 2-element tuple convention for result types.
  It will flag `{:ok, _, _}`, `{:error, _, _}`, or longer tuples anywhere they appear in the code.

  ## Examples

  These will trigger warnings:

      {:ok, value, metadata}           # 3 elements
      {:ok, data, meta, extra}         # 4 elements
      {:error, reason, details}        # 3 elements
      {:error, code, message, context} # 4 elements

  These are acceptable:

      :ok                              # atom only
      :error                           # atom only
      {:ok, value}                     # 2 elements - OK
      {:error, reason}                 # 2 elements - OK
      {:data, x, y, z}                 # non-result tuple - OK

  The check doesn't care about context - it flags these tuples whether they appear
  in function returns, arguments, pattern matches, variable assignments, or anywhere else.
  """

  use Credo.Check,
    id: "PL0002",
    base_priority: :high,
    category: :consistency,
    explanations: [
      check: """
      Avoid using 3+ element tuples with `:ok` or `:error` as the first element.

      Result tuples should follow the convention of being exactly 2 elements:
      `{:ok, value}` or `{:error, reason}`.

      If you need to return additional metadata, consider using a map or struct
      as the second element:

          # Instead of this
          {:ok, data, metadata}

          # Do this
          {:ok, %{data: data, metadata: metadata}}

      Or use a custom struct:

          {:ok, %Result{data: data, metadata: metadata}}
      """
    ]

  @doc false
  @impl true
  def run(source_file, params) do
    issue_meta = Credo.IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # Match 3+ element tuples with :ok as first element
  # AST pattern: {:{}, meta, [:ok, _, _, ...]}
  defp traverse({:{}, meta, [:ok | tail]} = ast, issues, issue_meta) when length(tail) >= 2 do
    {ast, [issue_for(issue_meta, meta[:line], :ok, length(tail) + 1) | issues]}
  end

  # Match 3+ element tuples with :error as first element
  # AST pattern: {:{}, meta, [:error, _, _, ...]}
  defp traverse({:{}, meta, [:error | tail]} = ast, issues, issue_meta) when length(tail) >= 2 do
    {ast, [issue_for(issue_meta, meta[:line], :error, length(tail) + 1) | issues]}
  end

  # Pass through all other AST nodes
  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp issue_for(issue_meta, line_no, atom, tuple_length) do
    format_issue(
      issue_meta,
      message: message_for(atom, tuple_length),
      line_no: line_no,
      trigger: inspect({atom, tuple_length})
    )
  end

  defp message_for(atom, tuple_length) do
    "Found #{tuple_length}-element #{inspect(atom)} tuple. " <>
      "Result tuples should be exactly 2 elements: #{inspect({atom, :_})}"
  end
end
