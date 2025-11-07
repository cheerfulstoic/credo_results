defmodule CredoResults.OnlyOkResultCheck do
  @moduledoc """
  A custom Credo check that flags functions that only ever return `:ok` or `{:ok, ...}` results
  without any `:error` cases.

  When a function never returns an error case, wrapping the result in `{:ok, ...}` adds
  unnecessary complexity. Consider returning the value directly instead.

  ## Examples

  This will trigger a warning:

      def fetch_user(id) do
        if id > 0 do
          {:ok, %User{id: id}}
        else
          {:ok, nil}  # Never returns an error
        end
      end

  This is also problematic:

      def process(data) do
        case data do
          :a -> {:ok, :a}
          :b -> {:ok, :b}
          :c -> {:ok, :c}
        end
      end

  Better alternatives:

      # Just return the value directly
      def fetch_user(id) do
        if id > 0 do
          %User{id: id}
        else
          nil
        end
      end

      # Or add proper error handling
      def fetch_user(id) do
        if id > 0 do
          {:ok, %User{id: id}}
        else
          {:error, :invalid_id}
        end
      end

  This is acceptable (has error cases):

      def fetch_user(id) do
        if id > 0 do
          {:ok, %User{id: id}}
        else
          {:error, :invalid_id}  # Proper error handling
        end
      end

  Single return paths are not flagged (may be intentional API design):

      def always_succeeds(val) do
        {:ok, val}
      end
  """

  use Credo.Check,
    id: "PL0003",
    run_on_all: true,
    base_priority: :high,
    category: :consistency,
    param_defaults: [include_single_expressions: false],
    explanations: [
      check: """
      Functions should only wrap results in `{:ok, ...}` tuples when they can also
      return error cases like `{:error, reason}`.

      ## Parameters

      - `include_single_expressions` (boolean, default: `false`): Set to `true` to also
        flag single-expression functions. By default, only multi-branch functions are flagged.

      If a function only ever returns `:ok` or `{:ok, value}` results without any
      error cases, consider returning the value directly instead.

      ## Why is this important?

      The `:ok`/`:error` tuple pattern is used to signal that an operation might fail.
      When a function never returns errors, wrapping values in `{:ok, ...}` tuples:

      - Adds unnecessary complexity
      - Forces callers to pattern match unnecessarily
      - Misleads readers into expecting error cases that don't exist
      - Makes the API harder to use

      ## Examples

          # Bad - no error cases, but wrapping in {:ok, ...}
          def fetch_user(id) do
            if id > 0 do
              {:ok, %User{id: id}}
            else
              {:ok, nil}
            end
          end

          # Good - return values directly
          def fetch_user(id) do
            if id > 0 do
              %User{id: id}
            else
              nil
            end
          end

          # Also good - proper error handling
          def fetch_user(id) do
            if id > 0 do
              {:ok, %User{id: id}}
            else
              {:error, :invalid_id}
            end
          end

      ## Configuration

      By default, this check does NOT flag single-expression functions or single-line
      pattern-matching clauses, as these might be part of an API design:

          # Not flagged by default - single expression
          def always_ok(val), do: {:ok, val}

          # Not flagged by default - each clause is a single expression
          def handle(:a), do: {:ok, :a}
          def handle(:b), do: {:ok, :b}

      To also flag single-expression functions, set `include_single_expressions: true`:

          {CredoResults.OnlyOkResultCheck, include_single_expressions: true}

      If you have a function that you intentionally want to always return `{:ok, ...}`
      for API consistency, you can disable this check for that function using a
      `# credo:disable-for-next-line` comment.
      """
    ]

  alias Credo.Check.Params
  alias Credo.IssueMeta
  alias Credo.SourceFile

  @doc false
  @impl true
  def run_on_all_source_files(exec, source_files, params) do
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
    ast = SourceFile.ast(source_file)

    # Get the option for including single expressions
    include_single_expressions = Params.get(params, :include_single_expressions, __MODULE__)

    ast
    |> collect_function_returns()
    |> Enum.flat_map(fn {function_name, line_no, returns} ->
      # Categorize returns (without deduplication, so we can count branches)
      {result_returns, non_result_returns} = categorize_returns(returns)

      # Check if this function only returns ok-style results (no errors)
      only_ok_returns = only_ok_style_returns?(result_returns)

      # Check if there's at least one tuple-wrapped return (bare :ok atoms alone are okay)
      has_tuple_wrapping = has_ok_tuple?(result_returns)

      # Check if this clause/function has multiple returns
      # Single-expression clauses (length == 1) might be part of multi-clause pattern matching
      # By default, we don't flag them unless include_single_expressions is true
      multiple_returns = length(returns) > 1

      # Determine if we should flag this function
      should_flag =
        only_ok_returns and non_result_returns == [] and has_tuple_wrapping and
          (multiple_returns or include_single_expressions)

      if should_flag do
        # Get unique patterns for the message
        unique_patterns = result_returns |> Enum.uniq() |> Enum.take(2)

        [
          format_issue(
            issue_meta,
            message: message_for(function_name, unique_patterns),
            trigger: function_name,
            line_no: line_no
          )
        ]
      else
        []
      end
    end)
  end

  # Collects all function definitions with their return values (WITHOUT deduplication)
  # This is a custom version that preserves duplicates so we can detect multiple branches
  defp collect_function_returns(ast) do
    {_ast, functions} =
      Macro.prewalk(ast, [], fn node, acc ->
        case node do
          # Match def and defp with guards
          {def_type, meta, [{:when, _, [{name, _, args}, _guard]} | [body]]}
          when def_type in [:def, :defp] and is_atom(name) and is_list(args) ->
            actual_body = Keyword.get(body, :do)
            returns = extract_returns_no_dedup(actual_body)
            function_name = "#{name}/#{length(args)}"
            {node, [{function_name, meta[:line], returns} | acc]}

          # Match def and defp without guards
          {def_type, meta, [{name, _, args} | [body]]}
          when def_type in [:def, :defp] and is_atom(name) and is_list(args) ->
            actual_body = Keyword.get(body, :do)
            returns = extract_returns_no_dedup(actual_body)
            function_name = "#{name}/#{length(args)}"
            {node, [{function_name, meta[:line], returns} | acc]}

          # Match single-clause function heads (no body) - skip them
          {def_type, _meta, [{name, _, args}]}
          when def_type in [:def, :defp] and is_atom(name) and is_list(args) ->
            {node, acc}

          _ ->
            {node, acc}
        end
      end)

    functions
  end

  # Extract returns WITHOUT deduplication (preserves branch count)
  defp extract_returns_no_dedup(body) do
    body
    |> collect_return_expressions()
    |> Enum.reject(&(&1 == :unknown))
  end

  # Recursively collect all expressions that could be returned
  # (Copied from Collector module but used without deduplication)
  defp collect_return_expressions(node) do
    case node do
      # Case statement - collect all clause returns
      {:case, _, [_condition, [do: clauses]]} when is_list(clauses) ->
        Enum.flat_map(clauses, fn
          {:->, _, [_pattern, body]} -> collect_return_expressions(body)
          _ -> []
        end)

      # Cond statement - collect all clause returns
      {:cond, _, [[do: clauses]]} when is_list(clauses) ->
        Enum.flat_map(clauses, fn
          {:->, _, [_condition, body]} -> collect_return_expressions(body)
          _ -> []
        end)

      # If/unless statement
      {:if, _, [_condition, blocks]} when is_list(blocks) ->
        Enum.flat_map(blocks, fn
          {:do, body} -> collect_return_expressions(body)
          {:else, body} -> collect_return_expressions(body)
          _ -> []
        end)

      {:unless, _, [_condition, blocks]} when is_list(blocks) ->
        Enum.flat_map(blocks, fn
          {:do, body} -> collect_return_expressions(body)
          {:else, body} -> collect_return_expressions(body)
          _ -> []
        end)

      # With statement - collect else clauses and main body
      {:with, _, args} when is_list(args) ->
        Enum.flat_map(args, fn
          [do: body] ->
            collect_return_expressions(body)

          [do: body, else: else_clauses] when is_list(else_clauses) ->
            main_returns = collect_return_expressions(body)

            else_returns =
              Enum.flat_map(else_clauses, fn
                {:->, _, [_pattern, clause_body]} -> collect_return_expressions(clause_body)
                _ -> []
              end)

            main_returns ++ else_returns

          _ ->
            []
        end)

      # Try-rescue-catch
      {:try, _, [blocks]} when is_list(blocks) ->
        Enum.flat_map(blocks, fn
          {:do, body} ->
            collect_return_expressions(body)

          {:rescue, clauses} when is_list(clauses) ->
            Enum.flat_map(clauses, fn
              {:->, _, [_pattern, body]} -> collect_return_expressions(body)
              _ -> []
            end)

          {:catch, clauses} when is_list(clauses) ->
            Enum.flat_map(clauses, fn
              {:->, _, [_pattern, body]} -> collect_return_expressions(body)
              _ -> []
            end)

          {:after, _body} ->
            # After blocks don't affect return value
            []

          {:else, clauses} when is_list(clauses) ->
            Enum.flat_map(clauses, fn
              {:->, _, [_pattern, body]} -> collect_return_expressions(body)
              _ -> []
            end)

          _ ->
            []
        end)

      # Block - the last expression is the return value
      {:__block__, _, expressions} when is_list(expressions) and expressions != [] ->
        last = List.last(expressions)
        collect_return_expressions(last)

      # For any other node, normalize it directly
      other ->
        [normalize_return(other)]
    end
  end

  # Normalize a return value to a pattern we can categorize
  # (Simplified version from Collector - only what we need)
  defp normalize_return(node) do
    case node do
      # Result tuple patterns
      :ok -> ":ok"
      :error -> ":error"
      {:ok, _} -> "{:ok, _}"
      {:error, _} -> "{:error, _}"

      # Literal tuple syntax (3+ elements)
      {:{}, _, [first | _rest]} when first in [:ok, :error] ->
        "{:#{first}, _, ...}"

      # Two-element tuple (might be result tuple or not)
      {left, right} when not is_list(right) ->
        case left do
          :ok -> "{:ok, _}"
          :error -> "{:error, _}"
          _ -> "{_, _}"
        end

      # Literal values
      true -> "true"
      false -> "false"
      nil -> "nil"
      atom when is_atom(atom) -> ":#{atom}"
      num when is_number(num) -> "#{num}"
      str when is_binary(str) -> "\"...\""

      # Lists
      list when is_list(list) and list != [] ->
        if Keyword.keyword?(list), do: :unknown, else: "[...]"

      [] -> "[]"

      # Other tuple
      {:{}, _, _} -> "{...}"
      {_, _} -> "{_, _}"

      # Map
      {:%{}, _, _} -> "%{...}"

      # Struct
      {:%, _, [_struct_name, {:%{}, _, _}]} -> "%Struct{}"

      # Pipe operator - get the final result
      {:|>, _, [_left, right]} ->
        normalize_return(right)

      # Function calls or other expressions - unknown
      _ ->
        :unknown
    end
  end

  # Categorize returns into result-style and non-result-style
  defp categorize_returns(returns) do
    Enum.split_with(returns, fn return ->
      case return do
        ":ok" -> true
        ":error" -> true
        "{:ok, " <> _ -> true
        "{:error, " <> _ -> true
        _ -> false
      end
    end)
  end

  # Check if all result returns are ok-style (no error returns)
  defp only_ok_style_returns?(result_returns) do
    # Must have at least one result return
    result_returns != [] and
      # All result returns must be ok-style (not error-style)
      Enum.all?(result_returns, fn return ->
        case return do
          ":ok" -> true
          "{:ok, " <> _ -> true
          _ -> false
        end
      end)
  end

  # Check if there's at least one tuple-wrapped ok return (not just bare :ok atoms)
  defp has_ok_tuple?(result_returns) do
    Enum.any?(result_returns, fn return ->
      case return do
        "{:ok, " <> _ -> true
        _ -> false
      end
    end)
  end

  defp message_for(function_name, result_returns) do
    examples = result_returns |> Enum.take(2) |> Enum.map_join(", ", &"`#{&1}`")

    "Function `#{function_name}` only returns :ok results (#{examples}) " <>
      "without any :error cases. Consider returning values directly " <>
      "instead of wrapping them in {:ok, ...} tuples."
  end
end
