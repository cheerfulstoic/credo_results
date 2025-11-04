defmodule CredoConsistentResultTypes.Lenient do
  @moduledoc """
  A **lenient** custom Credo check that ensures functions consistently return either:
  - Result-style returns: `:ok`, `:error`, or tuples starting with `:ok` or `:error` (any length)
  - Non-result-style returns: anything else (true, false, nil, lists, regular tuples, etc.)

  But not a mix of both styles.

  This check recognizes tuples of any length as result tuples, as long as they start
  with `:ok` or `:error`. For a stricter check that only accepts 2-element tuples,
  see `Plausible.ConsistentResultTypes.Strict`.

  ## Examples

  This is inconsistent and will trigger a warning:

      def fetch_user(id) do
        if id > 0 do
          {:ok, %User{id: id}}
        else
          false  # Mixing result tuple with boolean
        end
      end

  This is also inconsistent:

      def process(data) do
        if valid?(data) do
          {:ok, result, metadata}  # Result tuple
        else
          nil  # Non-result value
        end
      end

  This is consistent (any-length result tuples):

      def fetch_user(id) do
        if id > 0 do
          {:ok, %User{id: id}, metadata}  # 3-element tuple - OK!
        else
          {:error, :invalid_id}  # 2-element tuple - OK!
        end
      end

  Or this is also consistent:

      def valid_user?(id) do
        if id > 0 do
          true
        else
          false  # All non-result-style returns
        end
      end
  """

  use Credo.Check,
    id: "PL0001-lenient",
    run_on_all: true,
    base_priority: :high,
    category: :consistency,
    explanations: [
      check: """
      Functions should consistently return either **result-style returns**
      (`:ok`, `:error`, or tuples of any length starting with these atoms) or
      non-result-style values, but not a mix of both.

      This is the **lenient** variant that accepts result tuples of any length.
      For a stricter check that only accepts 2-element tuples, use
      `Plausible.ConsistentResultTypes.Strict`.

      Mixing return types makes functions harder to use and can lead to bugs:

          # This is bad - mixes result tuples with boolean
          def fetch_user(id) do
            if id > 0 do
              {:ok, %User{id: id}}
            else
              false
            end
          end

          # This is bad - mixes 3-element result tuple with nil
          def process(data) do
            if valid?(data) do
              {:ok, result, metadata}
            else
              nil
            end
          end

          # This is good - uses result-style returns consistently (any length)
          def fetch_user(id) do
            if id > 0 do
              {:ok, %User{id: id}, extra_data}
            else
              {:error, :invalid_id}
            end
          end

          # This is also good - uses booleans consistently
          def valid_user?(id) do
            id > 0
          end

      When using result-style returns, all returns should be `:ok`, `:error`,
      `{:ok, ...}`, or `{:error, ...}` (any length). When not using result-style
      returns, avoid these patterns entirely.
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
      # Use lenient categorization
      {result_returns, non_result_returns} = @collector.categorize_returns_lenient(returns)

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

    "Function `#{function_name}` has inconsistent return types: " <>
      "uses result-style returns (#{result_examples}) " <>
      "but also returns non-result values (#{non_result_examples})"
  end
end
