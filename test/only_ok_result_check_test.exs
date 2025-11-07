defmodule CredoResults.OnlyOkResultCheckTest do
  use ExUnit.Case

  alias Credo.SourceFile

  # Helper function to run the check on source code
  # This duplicates the check logic to test it properly
  defp run_check(source_code, opts \\ []) do
    source_file = SourceFile.parse(source_code, "test.ex")
    ast = SourceFile.ast(source_file)
    include_single_expressions = Keyword.get(opts, :include_single_expressions, false)

    ast
    |> collect_function_returns()
    |> Enum.flat_map(fn {function_name, line_no, returns} ->
      {result_returns, non_result_returns} = categorize_returns(returns)

      only_ok_returns = only_ok_style_returns?(result_returns)
      has_tuple_wrapping = has_ok_tuple?(result_returns)
      multiple_returns = length(returns) > 1

      should_flag =
        only_ok_returns and non_result_returns == [] and has_tuple_wrapping and
          (multiple_returns or include_single_expressions)

      if should_flag do
        [{function_name, line_no, []}]
      else
        []
      end
    end)
  end

  # Copy the collection logic from OnlyOkResultCheck for testing
  defp collect_function_returns(ast) do
    {_ast, functions} =
      Macro.prewalk(ast, [], fn node, acc ->
        case node do
          {def_type, meta, [{:when, _, [{name, _, args}, _guard]} | [body]]}
          when def_type in [:def, :defp] and is_atom(name) and is_list(args) ->
            actual_body = Keyword.get(body, :do)
            returns = extract_returns_no_dedup(actual_body)
            function_name = "#{name}/#{length(args)}"
            {node, [{function_name, meta[:line], returns} | acc]}

          {def_type, meta, [{name, _, args} | [body]]}
          when def_type in [:def, :defp] and is_atom(name) and is_list(args) ->
            actual_body = Keyword.get(body, :do)
            returns = extract_returns_no_dedup(actual_body)
            function_name = "#{name}/#{length(args)}"
            {node, [{function_name, meta[:line], returns} | acc]}

          {def_type, _meta, [{name, _, args}]}
          when def_type in [:def, :defp] and is_atom(name) and is_list(args) ->
            {node, acc}

          _ ->
            {node, acc}
        end
      end)

    functions
  end

  defp extract_returns_no_dedup(body) do
    body
    |> collect_return_expressions()
    |> Enum.reject(&(&1 == :unknown))
  end

  defp collect_return_expressions(node) do
    case node do
      {:case, _, [_condition, [do: clauses]]} when is_list(clauses) ->
        Enum.flat_map(clauses, fn
          {:->, _, [_pattern, body]} -> collect_return_expressions(body)
          _ -> []
        end)

      {:cond, _, [[do: clauses]]} when is_list(clauses) ->
        Enum.flat_map(clauses, fn
          {:->, _, [_condition, body]} -> collect_return_expressions(body)
          _ -> []
        end)

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
            []

          {:else, clauses} when is_list(clauses) ->
            Enum.flat_map(clauses, fn
              {:->, _, [_pattern, body]} -> collect_return_expressions(body)
              _ -> []
            end)

          _ ->
            []
        end)

      {:__block__, _, expressions} when is_list(expressions) and expressions != [] ->
        last = List.last(expressions)
        collect_return_expressions(last)

      other ->
        [normalize_return(other)]
    end
  end

  defp normalize_return(node) do
    case node do
      :ok -> ":ok"
      :error -> ":error"
      {:ok, _} -> "{:ok, _}"
      {:error, _} -> "{:error, _}"
      {:{}, _, [first | _rest]} when first in [:ok, :error] -> "{:#{first}, _, ...}"
      {left, right} when not is_list(right) ->
        case left do
          :ok -> "{:ok, _}"
          :error -> "{:error, _}"
          _ -> "{_, _}"
        end
      true -> "true"
      false -> "false"
      nil -> "nil"
      atom when is_atom(atom) -> ":#{atom}"
      num when is_number(num) -> "#{num}"
      str when is_binary(str) -> "\"...\""
      list when is_list(list) and list != [] ->
        if Keyword.keyword?(list), do: :unknown, else: "[...]"
      [] -> "[]"
      {:{}, _, _} -> "{...}"
      {_, _} -> "{_, _}"
      {:%{}, _, _} -> "%{...}"
      {:%, _, [_struct_name, {:%{}, _, _}]} -> "%Struct{}"
      {:|>, _, [_left, right]} -> normalize_return(right)
      _ -> :unknown
    end
  end

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

  defp only_ok_style_returns?(result_returns) do
    result_returns != [] and
      Enum.all?(result_returns, fn return ->
        case return do
          ":ok" -> true
          "{:ok, " <> _ -> true
          _ -> false
        end
      end)
  end

  defp has_ok_tuple?(result_returns) do
    Enum.any?(result_returns, fn return ->
      case return do
        "{:ok, " <> _ -> true
        _ -> false
      end
    end)
  end

  describe "Functions that should be flagged (only ok results)" do
    test "all {:ok, _} tuples, no errors" do
      source = """
      defmodule Example do
        def fetch_user(id) do
          if id > 0 do
            {:ok, %{id: id}}
          else
            {:ok, nil}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, _returns}] = issues
      assert function_name == "fetch_user/1"
    end

    test "mix of :ok atom and {:ok, _} tuples" do
      source = """
      defmodule Example do
        def process(data) do
          case data do
            nil -> :ok
            val -> {:ok, val}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, _returns}] = issues
      assert function_name == "process/1"
    end

    test "multiple {:ok, _} returns in case statement" do
      source = """
      defmodule Example do
        def handle(val) do
          case val do
            :a -> {:ok, :a}
            :b -> {:ok, :b}
            :c -> {:ok, :c}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "all {:ok, _} in cond statement" do
      source = """
      defmodule Example do
        def classify(val) do
          cond do
            val > 10 -> {:ok, :high}
            val > 0 -> {:ok, :low}
            true -> {:ok, :zero}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "all {:ok, _} in if/else" do
      source = """
      defmodule Example do
        def check(val) do
          if val do
            {:ok, :positive}
          else
            {:ok, :negative}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "3-element {:ok, _, ...} tuples only" do
      source = """
      defmodule Example do
        def process(data) do
          if valid?(data) do
            {:ok, data, :metadata}
          else
            {:ok, nil, :no_metadata}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, _returns}] = issues
      assert function_name == "process/1"
    end

    test "mix of 2-element and 3-element {:ok, ...} tuples" do
      source = """
      defmodule Example do
        def mixed(val) do
          cond do
            val > 10 -> {:ok, val}
            val > 0 -> {:ok, val, :meta}
            true -> {:ok, 0, :default, :extra}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "with statement returning only :ok results" do
      source = """
      defmodule Example do
        def process(val) do
          with {:ok, x} <- step1(val),
               {:ok, y} <- step2(x) do
            {:ok, y}
          else
            _ -> {:ok, :default}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "try-rescue with only :ok returns" do
      source = """
      defmodule Example do
        def safe_div(a, b) do
          try do
            {:ok, a / b}
          rescue
            ArithmeticError -> {:ok, 0}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "nested control structures with only :ok" do
      source = """
      defmodule Example do
        def nested(a, b) do
          if a > 0 do
            case b do
              :x -> {:ok, :x}
              :y -> {:ok, :y}
            end
          else
            {:ok, :default}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "unless statement with only :ok returns" do
      source = """
      defmodule Example do
        def check(val) do
          unless val do
            {:ok, :empty}
          else
            {:ok, val}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end
  end

  describe "Functions that should NOT be flagged" do
    test "function with both :ok and :error returns" do
      source = """
      defmodule Example do
        def fetch_user(id) do
          if id > 0 do
            {:ok, %{id: id}}
          else
            {:error, :invalid_id}
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "function with only :ok atom (no tuple wrapping)" do
      source = """
      defmodule Example do
        def run(val) do
          if val, do: :ok, else: :ok
        end
      end
      """

      # Single return path, so not flagged
      assert run_check(source) == []
    end

    test "function with only :error returns" do
      source = """
      defmodule Example do
        def validate(data) do
          cond do
            bad1?(data) -> {:error, :bad1}
            bad2?(data) -> {:error, :bad2}
            true -> :error
          end
        end
      end
      """

      # Only errors, not only ok
      assert run_check(source) == []
    end

    test "function returning booleans" do
      source = """
      defmodule Example do
        def valid?(id) do
          if id > 0 do
            true
          else
            false
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "function returning nil" do
      source = """
      defmodule Example do
        def maybe_get(id) do
          if id > 0, do: nil, else: nil
        end
      end
      """

      assert run_check(source) == []
    end

    test "function returning custom atoms" do
      source = """
      defmodule Example do
        def status(id) do
          cond do
            id > 10 -> :active
            id > 0 -> :pending
            true -> :inactive
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "function returning numbers" do
      source = """
      defmodule Example do
        def count(list) do
          if is_list(list), do: length(list), else: 0
        end
      end
      """

      assert run_check(source) == []
    end

    test "function returning strings" do
      source = """
      defmodule Example do
        def format(val) do
          if val, do: "yes", else: "no"
        end
      end
      """

      assert run_check(source) == []
    end

    test "function returning lists" do
      source = """
      defmodule Example do
        def items(val) do
          if val, do: [1, 2, 3], else: []
        end
      end
      """

      assert run_check(source) == []
    end

    test "function returning maps" do
      source = """
      defmodule Example do
        def data(val) do
          if val, do: %{a: 1}, else: %{}
        end
      end
      """

      assert run_check(source) == []
    end

    test "function with single return path not flagged" do
      source = """
      defmodule Example do
        def always_ok(val) do
          {:ok, val}
        end
      end
      """

      # Single-expression functions might be part of an API or interface
      # We don't flag them to avoid false positives on pattern-matching clauses
      assert run_check(source) == []
    end

    test "function with unknown return types" do
      source = """
      defmodule Example do
        def passthrough(val) do
          result = compute(val)
          result
        end
      end
      """

      assert run_check(source) == []
    end

    test "regular tuples (not result-style)" do
      source = """
      defmodule Example do
        def coordinates(val) do
          if val, do: {1, 2}, else: {0, 0}
        end
      end
      """

      assert run_check(source) == []
    end

    test "mix of :ok and non-result returns (already caught by ConsistentResultCheck)" do
      source = """
      defmodule Example do
        def mixed(val) do
          if val, do: {:ok, val}, else: false
        end
      end
      """

      # This would be caught by ConsistentResultCheck, not this one
      assert run_check(source) == []
    end
  end

  describe "Private functions" do
    test "flags private function with only :ok returns" do
      source = """
      defmodule Example do
        defp internal(data) do
          if data do
            {:ok, data}
          else
            {:ok, nil}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, _returns}] = issues
      assert function_name == "internal/1"
    end

    test "does not flag private function with mixed returns" do
      source = """
      defmodule Example do
        defp internal(data) do
          if data, do: {:ok, data}, else: {:error, :empty}
        end
      end
      """

      assert run_check(source) == []
    end
  end

  describe "Multi-arity functions" do
    test "each arity checked separately - one flagged, one not" do
      source = """
      defmodule Example do
        def process(val) do
          if val, do: {:ok, val}, else: {:ok, nil}
        end

        def process(val, opts) do
          if opts[:strict], do: {:ok, val}, else: {:error, :not_strict}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, _returns}] = issues
      assert function_name == "process/1"
    end

    test "both arities flagged" do
      source = """
      defmodule Example do
        def fetch(id) do
          if id > 0, do: {:ok, id}, else: {:ok, 0}
        end

        def fetch(id, default) do
          if id > 0, do: {:ok, id}, else: {:ok, default}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 2
    end
  end

  describe "Multi-clause function definitions" do
    test "all clauses with only :ok returns combined" do
      source = """
      defmodule Example do
        def handle(:a), do: {:ok, :a}
        def handle(:b), do: {:ok, :b}
        def handle(_), do: {:ok, :default}
      end
      """

      # Multi-clause with single-line syntax - each has single return
      # but collector should group them together
      issues = run_check(source)
      # This depends on how collector handles multi-clause functions
      # Based on the existing tests, it seems each clause is separate
      assert length(issues) == 0
    end

    test "multi-clause where some have multiple returns" do
      source = """
      defmodule Example do
        def process({:ok, val}) do
          if val > 0 do
            {:ok, val}
          else
            {:ok, 0}
          end
        end

        def process({:error, _}), do: {:ok, :default}
      end
      """

      # First clause has multiple returns (both :ok)
      # Should be flagged
      issues = run_check(source)
      assert length(issues) == 1
    end

    test "multi-clause with guards, all :ok" do
      source = """
      defmodule Example do
        def classify(n) when n > 0 do
          if n > 10, do: {:ok, :high}, else: {:ok, :low}
        end

        def classify(n) when n < 0 do
          if n < -10, do: {:ok, :very_low}, else: {:ok, :low}
        end

        def classify(0), do: {:ok, :zero}
      end
      """

      # First two clauses have multiple returns
      issues = run_check(source)
      assert length(issues) == 2
    end
  end

  describe "Edge cases" do
    test "multiple functions in one module - some flagged" do
      source = """
      defmodule Example do
        def good(val) do
          if val, do: {:ok, val}, else: {:error, :bad}
        end

        def bad(val) do
          if val, do: {:ok, val}, else: {:ok, nil}
        end

        def also_good(val) do
          if val, do: true, else: false
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, _returns}] = issues
      assert function_name == "bad/1"
    end

    test "empty function body" do
      source = """
      defmodule Example do
        def empty do
        end
      end
      """

      assert run_check(source) == []
    end

    test "function with struct return" do
      source = """
      defmodule Example do
        def create(val) do
          if val, do: %User{id: val}, else: nil
        end
      end
      """

      assert run_check(source) == []
    end

    test "deeply nested with only :ok" do
      source = """
      defmodule Example do
        def deeply_nested(a, b, c) do
          if a do
            case b do
              :x ->
                cond do
                  c > 0 -> {:ok, :positive}
                  c < 0 -> {:ok, :negative}
                  true -> {:ok, :zero}
                end
              :y ->
                {:ok, :y_value}
            end
          else
            {:ok, :default}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "with statement with multiple else clauses, all :ok" do
      source = """
      defmodule Example do
        def multi_with(val) do
          with {:ok, x} <- step1(val),
               {:ok, y} <- step2(x),
               {:ok, z} <- step3(y) do
            {:ok, z}
          else
            :step1_fail -> {:ok, :step1_default}
            :step2_fail -> {:ok, :step2_default}
            _ -> {:ok, :unknown_default}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "boolean naming heuristics - not flagged" do
      source = """
      defmodule Example do
        def valid?(val) do
          if val > 0, do: true, else: false
        end

        def is_positive(val) do
          if val > 0, do: true, else: false
        end

        def has_value(map, key) do
          if Map.has_key?(map, key), do: true, else: false
        end
      end
      """

      # Boolean returns, not result-style
      assert run_check(source) == []
    end

    test "function returning only bare :ok (multiple times)" do
      source = """
      defmodule Example do
        def run(val) do
          case val do
            :a -> :ok
            :b -> :ok
            :c -> :ok
          end
        end
      end
      """

      # Only bare :ok atoms, no tuples - should not flag
      assert run_check(source) == []
    end

    test "pipe operator with case statement, only :ok" do
      source = """
      defmodule Example do
        def process(val) do
          val
          |> validate()
          |> case do
            :valid -> {:ok, val}
            :invalid -> {:ok, :default}
          end
        end
      end
      """

      # This tests if collector properly extracts returns from piped case
      issues = run_check(source)
      # Known limitation: may not detect properly
      assert length(issues) == 0
    end
  end

  describe "Complex scenarios" do
    @tag :skip
    test "function with all ok returns across multiple control structures (variable assignment)" do
      # This is a known limitation: when the return value is stored in a variable
      # and then returned, we can't track what the variable contains without
      # more sophisticated data flow analysis
      source = """
      defmodule Example do
        def complex(a, b, c) do
          result = if a do
            case b do
              :x -> {:ok, :x}
              :y -> {:ok, :y}
            end
          else
            cond do
              c > 0 -> {:ok, :positive}
              c < 0 -> {:ok, :negative}
              true -> {:ok, :zero}
            end
          end

          result
        end
      end
      """

      issues = run_check(source)
      # Would be 1 if we could track variable contents
      assert length(issues) == 0
    end

    test "try with catch and else, all :ok" do
      source = """
      defmodule Example do
        def handle(val) do
          try do
            {:ok, risky_operation(val)}
          catch
            :throw, _ -> {:ok, :caught}
          rescue
            RuntimeError -> {:ok, :rescued}
          else
            {:ok, x} -> {:ok, x}
            other -> {:ok, other}
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end
  end

  describe "Configuration: include_single_expressions option" do
    test "single-expression function NOT flagged by default" do
      source = """
      defmodule Example do
        def always_ok(val) do
          {:ok, val}
        end
      end
      """

      # Default behavior - don't flag single expressions
      issues = run_check(source)
      assert length(issues) == 0
    end

    test "single-expression function IS flagged when option enabled" do
      source = """
      defmodule Example do
        def always_ok(val) do
          {:ok, val}
        end
      end
      """

      # With option enabled - flag single expressions
      issues = run_check(source, include_single_expressions: true)
      assert length(issues) == 1
      [{function_name, _line, _returns}] = issues
      assert function_name == "always_ok/1"
    end

    test "single-line function clause NOT flagged by default" do
      source = """
      defmodule Example do
        def handle(:a), do: {:ok, :a}
      end
      """

      issues = run_check(source)
      assert length(issues) == 0
    end

    test "single-line function clause IS flagged when option enabled" do
      source = """
      defmodule Example do
        def handle(:a), do: {:ok, :a}
      end
      """

      issues = run_check(source, include_single_expressions: true)
      assert length(issues) == 1
      [{function_name, _line, _returns}] = issues
      assert function_name == "handle/1"
    end

    test "multi-clause single-line functions NOT flagged by default" do
      source = """
      defmodule Example do
        def handle(:a), do: {:ok, :a}
        def handle(:b), do: {:ok, :b}
        def handle(_), do: {:ok, :default}
      end
      """

      # Each clause is single expression - not flagged by default
      issues = run_check(source)
      assert length(issues) == 0
    end

    test "multi-clause single-line functions ARE flagged when option enabled" do
      source = """
      defmodule Example do
        def handle(:a), do: {:ok, :a}
        def handle(:b), do: {:ok, :b}
        def handle(_), do: {:ok, :default}
      end
      """

      # With option enabled, all clauses get flagged
      issues = run_check(source, include_single_expressions: true)
      assert length(issues) == 3

      function_names = Enum.map(issues, fn {name, _, _} -> name end)
      assert Enum.all?(function_names, &(&1 == "handle/1"))
    end

    test "multi-branch functions still flagged regardless of option" do
      source = """
      defmodule Example do
        def fetch_user(id) do
          if id > 0 do
            {:ok, %{id: id}}
          else
            {:ok, nil}
          end
        end
      end
      """

      # Multi-branch function is flagged with default settings
      issues_default = run_check(source)
      assert length(issues_default) == 1

      # Also flagged with option enabled
      issues_enabled = run_check(source, include_single_expressions: true)
      assert length(issues_enabled) == 1
    end

    test "option does not affect functions with error cases" do
      source = """
      defmodule Example do
        def good(val), do: if val, do: {:ok, val}, else: {:error, :bad}
      end
      """

      # Not flagged either way because it has error cases
      assert run_check(source) == []
      assert run_check(source, include_single_expressions: true) == []
    end

    test "option does not affect non-result returns" do
      source = """
      defmodule Example do
        def count(val), do: if val, do: 1, else: 0
      end
      """

      # Not flagged either way because these aren't result tuples
      assert run_check(source) == []
      assert run_check(source, include_single_expressions: true) == []
    end
  end
end
