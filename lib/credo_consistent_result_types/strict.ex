defmodule CredoConsistentResultTypes.Strict do
  @moduledoc """
  A **strict** custom Credo check that ensures functions consistently return either:
  - Result-tuple style: `:ok`, `{:ok, term()}`, `:error`, `{:error, term()}` (2-element tuples only)
  - Non-result-tuple style: anything else (true, false, nil, lists, etc.)

  But not a mix of both styles.

  This check only recognizes 2-element result tuples. For a more lenient check that
  accepts tuples of any length, see `Plausible.ConsistentResultTypes.Lenient`.

  ## Examples

  This is inconsistent and will trigger a warning:

      def fetch_user(id) do
        if id > 0 do
          {:ok, %User{id: id}}
        else
          false  # Mixing result tuple with boolean
        end
      end

  This is also inconsistent (3-element tuple not recognized as result tuple):

      def process(data) do
        if valid?(data) do
          {:ok, result, metadata}  # 3-element tuple - not recognized
        else
          nil
        end
      end

  This is consistent:

      def fetch_user(id) do
        if id > 0 do
          {:ok, %User{id: id}}
        else
          {:error, :invalid_id}  # All 2-element result tuples
        end
      end

  Or this is also consistent:

      def valid_user?(id) do
        if id > 0 do
          true
        else
          false  # All non-result-tuple returns
        end
      end
  """

  use Credo.Check,
    id: "PL0001-strict",
    run_on_all: true,
    base_priority: :high,
    category: :consistency,
    explanations: [
      check: """
      Functions should consistently return either **2-element** result tuples
      (`:ok`, `{:ok, term()}`, `:error`, `{:error, term()}`) or non-result-tuple
      values, but not a mix of both styles.

      This is the **strict** variant that only recognizes 2-element result tuples.
      For a lenient check that accepts any-length result tuples, use
      `Plausible.ConsistentResultTypes.Lenient`.

      Mixing return types makes functions harder to use and can lead to bugs:

          # This is bad - mixes result tuples with boolean
          def fetch_user(id) do
            if id > 0 do
              {:ok, %User{id: id}}
            else
              false
            end
          end

          # This is good - uses 2-element result tuples consistently
          def fetch_user(id) do
            if id > 0 do
              {:ok, %User{id: id}}
            else
              {:error, :invalid_id}
            end
          end

          # This is also good - uses booleans consistently
          def valid_user?(id) do
            id > 0
          end

      When using result tuples in this strict mode, all returns should be `:ok`,
      `{:ok, value}`, `:error`, or `{:error, reason}` (2 elements only).
      Tuples with 3+ elements are not considered result tuples by this check.
      """
    ]

  alias Credo.IssueMeta
  alias Credo.SourceFile
  alias Plausible.ConsistentResultTypes.Collector

  @collector Collector

  @doc false
  @impl true
  def run_on_all_source_files(exec, source_files, params) do
    # We don't use the standard collector pattern because we want to check
    # each function individually, not enforce consistency across files
    source_files
    |> Task.async_stream(
      fn source_file ->
        issues = find_issues_in_file(source_file, params)
        {source_file, issues}
      end,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.each(fn {:ok, {_source_file, issues}} ->
      if issues != [] do
        Credo.Execution.ExecutionIssues.append(exec, issues)
      end
    end)

    :ok
  end

  defp find_issues_in_file(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> @collector.find_inconsistent_functions()
    |> Enum.flat_map(fn {function_name, line_no, returns} ->
      # Use strict categorization
      {result_returns, non_result_returns} = @collector.categorize_returns_strict(returns)

      # Only report if inconsistent
      if result_returns != [] and non_result_returns != [] do
        [
          format_issue(
            issue_meta,
            message: message_for(function_name, result_returns, non_result_returns),
            trigger: function_name,
            line_no: line_no
          )
        ]
      else
        []
      end
    end)
  end

  defp message_for(function_name, result_returns, non_result_returns) do
    result_examples = result_returns |> Enum.take(2) |> Enum.map_join(", ", &"`#{&1}`")
    non_result_examples = non_result_returns |> Enum.take(2) |> Enum.map_join(", ", &"`#{&1}`")

    "Function `#{function_name}` has inconsistent return types (strict 2-element check): " <>
      "uses 2-element result tuples (#{result_examples}) " <>
      "but also returns non-result values (#{non_result_examples})"
  end
end
