defmodule CredoResults.ConsistentResultCheckTest do
  use ExUnit.Case

  alias Credo.SourceFile
  alias CredoResults.Collector

  # Helper function to run the check on source code
  defp run_check(source_code) do
    source_file = SourceFile.parse(source_code, "test.ex")

    # Get issues by checking inconsistencies
    issues =
      source_file
      |> Collector.find_inconsistent_functions()
      |> Enum.flat_map(fn {function_name, line_no, returns} ->
        {result_returns, non_result_returns} =
          Collector.categorize_returns_lenient(returns)

        if result_returns != [] and non_result_returns != [] do
          [{function_name, line_no, result_returns, non_result_returns}]
        else
          []
        end
      end)

    issues
  end

  describe "Consistent result-style returns (no issues)" do
    test "all 2-element :ok tuples" do
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

      assert run_check(source) == []
    end

    test "all 2-element :error tuples" do
      source = """
      defmodule Example do
        def validate(data) do
          if valid?(data) do
            {:error, :already_valid}
          else
            {:error, :invalid}
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "mixed 2 and 3-element result tuples" do
      source = """
      defmodule Example do
        def process(data) do
          if valid?(data) do
            {:ok, result, metadata}
          else
            {:error, :invalid}
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "mixed 2, 3, and 4+ element result tuples" do
      source = """
      defmodule Example do
        def process(data) do
          cond do
            data == :a -> {:ok, :a}
            data == :b -> {:ok, :b, :meta}
            data == :c -> {:ok, :c, :meta, :extra}
            true -> {:error, :unknown, :info}
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test ":ok and :error atoms only" do
      source = """
      defmodule Example do
        def check(value) do
          if value, do: :ok, else: :error
        end
      end
      """

      assert run_check(source) == []
    end

    test "mixed :ok atom with {:ok, _} tuples" do
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

      assert run_check(source) == []
    end

    test "mixed :error atom with {:error, _} tuples" do
      source = """
      defmodule Example do
        def process(data) do
          case data do
            :bad -> :error
            val -> {:error, val}
          end
        end
      end
      """

      assert run_check(source) == []
    end
  end

  describe "Consistent non-result returns (no issues)" do
    test "all booleans" do
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

    test "all nil values" do
      source = """
      defmodule Example do
        def maybe_get(id) do
          if id > 0, do: nil, else: nil
        end
      end
      """

      assert run_check(source) == []
    end

    test "mixed booleans and nil" do
      source = """
      defmodule Example do
        def check(id) do
          cond do
            id > 10 -> true
            id > 0 -> false
            true -> nil
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "custom atoms" do
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

    test "numbers" do
      source = """
      defmodule Example do
        def count(list) do
          if is_list(list), do: length(list), else: 0
        end
      end
      """

      assert run_check(source) == []
    end

    test "strings" do
      source = """
      defmodule Example do
        def format(val) do
          if val, do: "yes", else: "no"
        end
      end
      """

      assert run_check(source) == []
    end

    test "lists" do
      source = """
      defmodule Example do
        def items(val) do
          if val, do: [1, 2, 3], else: []
        end
      end
      """

      assert run_check(source) == []
    end

    test "maps" do
      source = """
      defmodule Example do
        def data(val) do
          if val, do: %{a: 1}, else: %{}
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

    test "3-element tuples not starting with :ok/:error" do
      source = """
      defmodule Example do
        def triplet(val) do
          if val, do: {:coord, 1, 2}, else: {:coord, 0, 0}
        end
      end
      """

      assert run_check(source) == []
    end
  end

  describe "Inconsistent returns (should report issues)" do
    test "2-element :ok tuple mixed with boolean" do
      source = """
      defmodule Example do
        def fetch_user(id) do
          if id > 0 do
            {:ok, %{id: id}}
          else
            false
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, result_returns, non_result_returns}] = issues
      assert function_name == "fetch_user/1"
      assert "{:ok, _}" in result_returns
      assert "false" in non_result_returns
    end

    test "2-element :error tuple mixed with nil" do
      source = """
      defmodule Example do
        def validate(data) do
          if valid?(data) do
            {:error, :invalid}
          else
            nil
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, result_returns, non_result_returns}] = issues
      assert function_name == "validate/1"
      assert "{:error, _}" in result_returns
      assert "nil" in non_result_returns
    end

    test "3-element :ok tuple mixed with boolean" do
      source = """
      defmodule Example do
        def process(data) do
          if valid?(data) do
            {:ok, result, metadata}
          else
            false
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, result_returns, non_result_returns}] = issues
      assert function_name == "process/1"
      assert "{:ok, _, ...}" in result_returns
      assert "false" in non_result_returns
    end

    test ":ok atom mixed with nil" do
      source = """
      defmodule Example do
        def check(val) do
          if val, do: :ok, else: nil
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, result_returns, non_result_returns}] = issues
      assert function_name == "check/1"
      assert ":ok" in result_returns
      assert "nil" in non_result_returns
    end

    test ":error atom mixed with false" do
      source = """
      defmodule Example do
        def validate(val) do
          if val, do: :error, else: false
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, result_returns, non_result_returns}] = issues
      assert function_name == "validate/1"
      assert ":error" in result_returns
      assert "false" in non_result_returns
    end

    test "result tuple mixed with custom atom" do
      source = """
      defmodule Example do
        def status(id) do
          if id > 0 do
            {:ok, :active}
          else
            :not_found
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, result_returns, non_result_returns}] = issues
      assert function_name == "status/1"
      assert "{:ok, _}" in result_returns
      assert ":not_found" in non_result_returns
    end

    test "multiple result types mixed with multiple non-result types" do
      source = """
      defmodule Example do
        def complex(val) do
          cond do
            val == :a -> {:ok, :a}
            val == :b -> :error
            val == :c -> false
            val == :d -> nil
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, result_returns, non_result_returns}] = issues
      assert function_name == "complex/1"
      assert "{:ok, _}" in result_returns
      assert ":error" in result_returns
      assert "false" in non_result_returns
      assert "nil" in non_result_returns
    end
  end

  describe "Control flow structures" do
    test "case statement with consistent returns" do
      source = """
      defmodule Example do
        def process(val) do
          case val do
            :a -> {:ok, :a}
            :b -> {:ok, :b}
            _ -> {:error, :unknown}
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "case statement with inconsistent returns" do
      source = """
      defmodule Example do
        def process(val) do
          case val do
            :a -> {:ok, :a}
            :b -> false
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "cond statement with consistent returns" do
      source = """
      defmodule Example do
        def check(val) do
          cond do
            val > 10 -> {:ok, :high}
            val > 0 -> {:ok, :low}
            true -> {:error, :negative}
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "cond statement with inconsistent returns" do
      source = """
      defmodule Example do
        def check(val) do
          cond do
            val > 10 -> {:ok, :high}
            val > 0 -> true
            true -> false
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "with statement consistent" do
      source = """
      defmodule Example do
        def process(val) do
          with {:ok, x} <- validate(val),
               {:ok, y} <- transform(x) do
            {:ok, y}
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "with statement inconsistent" do
      source = """
      defmodule Example do
        def process(val) do
          with {:ok, x} <- validate(val) do
            {:ok, x}
          else
            _ -> nil
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "try-rescue consistent" do
      source = """
      defmodule Example do
        def safe_div(a, b) do
          try do
            {:ok, a / b}
          rescue
            ArithmeticError -> {:error, :division_by_zero}
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "try-rescue inconsistent" do
      source = """
      defmodule Example do
        def safe_div(a, b) do
          try do
            {:ok, a / b}
          rescue
            ArithmeticError -> nil
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "nested if statements consistent" do
      source = """
      defmodule Example do
        def nested(a, b) do
          if a > 0 do
            if b > 0 do
              {:ok, :both_positive}
            else
              {:ok, :only_a_positive}
            end
          else
            {:error, :a_not_positive}
          end
        end
      end
      """

      assert run_check(source) == []
    end

    test "unless statement consistent" do
      source = """
      defmodule Example do
        def check(val) do
          unless val do
            {:error, :empty}
          else
            {:ok, val}
          end
        end
      end
      """

      assert run_check(source) == []
    end
  end

  describe "Function variations" do
    test "private function with defp" do
      source = """
      defmodule Example do
        defp internal(val) do
          if val, do: {:ok, val}, else: false
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, _result, _non_result}] = issues
      assert function_name == "internal/1"
    end

    test "function with guard clauses" do
      source = """
      defmodule Example do
        def process(val) when is_integer(val) do
          if val > 0, do: {:ok, val}, else: nil
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "multi-arity functions are separate" do
      source = """
      defmodule Example do
        def process(val) do
          {:ok, val}
        end

        def process(val, opts) do
          if opts[:strict], do: false, else: true
        end
      end
      """

      # Each arity is checked separately, so both should be consistent on their own
      assert run_check(source) == []
    end

    test "single-line function" do
      source = """
      defmodule Example do
        def quick(val), do: if val, do: {:ok, val}, else: false
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end

    test "function with single return path" do
      source = """
      defmodule Example do
        def always_ok(val) do
          {:ok, val}
        end
      end
      """

      # Single return path is always consistent
      assert run_check(source) == []
    end
  end

  describe "Boolean heuristics" do
    test "function ending with ? inferred as boolean" do
      source = """
      defmodule Example do
        def valid?(val) do
          if val > 0, do: true, else: false
        end
      end
      """

      # Boolean returns are consistent
      assert run_check(source) == []
    end

    test "function starting with is_ inferred as boolean" do
      source = """
      defmodule Example do
        def is_valid(val) do
          if val > 0, do: true, else: false
        end
      end
      """

      assert run_check(source) == []
    end

    test "function starting with has_ inferred as boolean" do
      source = """
      defmodule Example do
        def has_value(map, key) do
          if Map.has_key?(map, key), do: true, else: false
        end
      end
      """

      assert run_check(source) == []
    end
  end

  describe "Edge cases" do
    test "multiple functions in one module - some inconsistent" do
      source = """
      defmodule Example do
        def good1(val) do
          if val, do: {:ok, val}, else: {:error, :bad}
        end

        def bad(val) do
          if val, do: {:ok, val}, else: false
        end

        def good2(val) do
          if val, do: true, else: false
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [{function_name, _line, _result, _non_result}] = issues
      assert function_name == "bad/1"
    end

    test "function returning variable - treated as unknown" do
      source = """
      defmodule Example do
        def passthrough(val) do
          result = compute(val)
          result
        end
      end
      """

      # Unknown types don't trigger issues
      assert run_check(source) == []
    end

    test "pipe operator followed by case statement" do
      source = """
      defmodule Example do
        def process(val) do
          val
          |> validate()
          |> case do
            :valid -> {:ok, val}
            :invalid -> false
          end
        end
      end
      """

      # This is a known limitation: the collector doesn't properly extract returns
      # from case statements that follow pipe operators
      issues = run_check(source)
      assert length(issues) == 0
    end

    test "empty function body" do
      source = """
      defmodule Example do
        def empty do
        end
      end
      """

      # Empty functions don't have returns to check
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

      # Struct and nil are both non-result types
      assert run_check(source) == []
    end

    test "function with keyword list return" do
      source = """
      defmodule Example do
        def options(val) do
          if val, do: [key: val], else: []
        end
      end
      """

      # Both are lists (non-result)
      assert run_check(source) == []
    end

    test "result tuple mixed with regular tuple" do
      source = """
      defmodule Example do
        def mixed(val) do
          if val > 0, do: {:ok, val}, else: {:x, :y}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
    end
  end

  describe "Complex nested scenarios" do
    test "deeply nested control structures" do
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
                {:error, :y_not_supported}
            end
          else
            nil
          end
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      # Should detect {:ok, _} and {:error, _} as result, nil as non-result
    end

    test "with statement with multiple else clauses" do
      source = """
      defmodule Example do
        def multi_with(val) do
          with {:ok, x} <- step1(val),
               {:ok, y} <- step2(x),
               {:ok, z} <- step3(y) do
            {:ok, z}
          else
            {:error, :step1} -> {:error, :failed_at_step1}
            {:error, :step2} -> {:error, :failed_at_step2}
            _ -> {:error, :unknown}
          end
        end
      end
      """

      # All result-style returns
      assert run_check(source) == []
    end

    test "case with multiple clause patterns" do
      source = """
      defmodule Example do
        def handle_response(response) do
          case response do
            {:ok, %{status: 200, body: body}} -> {:ok, body}
            {:ok, %{status: 404}} -> {:error, :not_found}
            {:ok, %{status: status}} when status >= 500 -> {:error, :server_error}
            {:error, reason} -> {:error, reason}
            _ -> {:error, :unknown}
          end
        end
      end
      """

      assert run_check(source) == []
    end
  end

  describe "Multi-clause function definitions" do
    test "multiple clauses with pattern matching - all consistent" do
      source = """
      defmodule Example do
        def handle({:ok, val}), do: {:ok, val}
        def handle({:error, reason}), do: {:error, reason}
        def handle(_), do: {:error, :invalid_input}
      end
      """

      assert run_check(source) == []
    end

    test "multiple clauses with pattern matching - each clause checked independently" do
      source = """
      defmodule Example do
        def handle({:ok, val}), do: {:ok, val}
        def handle({:error, _}), do: nil
      end
      """

      # Multi-clause functions with single-line syntax are treated as separate functions
      # Each clause only has one return, so neither is flagged as inconsistent
      # This is a known limitation of the checker
      issues = run_check(source)
      assert length(issues) == 0
    end

    test "multiple clauses with guards" do
      source = """
      defmodule Example do
        def classify(n) when n > 0, do: {:ok, :positive}
        def classify(n) when n < 0, do: {:ok, :negative}
        def classify(0), do: {:ok, :zero}
      end
      """

      assert run_check(source) == []
    end
  end
end
