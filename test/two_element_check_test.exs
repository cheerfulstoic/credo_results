defmodule CredoResults.TwoElementCheckTest do
  use ExUnit.Case

  alias CredoResults.TwoElementCheck

  # Helper function to run the check on source code
  defp run_check(source_code) do
    source_code
    |> Credo.SourceFile.parse("test.ex")
    |> TwoElementCheck.run([])
    |> Enum.sort_by(& &1.line_no)
  end

  # Helper to count issues
  defp issue_count(source_code) do
    source_code |> run_check() |> length()
  end

  describe "Valid 2-element result tuples (no issues)" do
    test "2-element :ok tuple" do
      source = """
      defmodule Example do
        def process(data) do
          {:ok, data}
        end
      end
      """

      assert issue_count(source) == 0
    end

    test "2-element :error tuple" do
      source = """
      defmodule Example do
        def validate(data) do
          {:error, :invalid}
        end
      end
      """

      assert issue_count(source) == 0
    end

    test "bare :ok atom" do
      source = """
      defmodule Example do
        def run, do: :ok
      end
      """

      assert issue_count(source) == 0
    end

    test "bare :error atom" do
      source = """
      defmodule Example do
        def fail, do: :error
      end
      """

      assert issue_count(source) == 0
    end

    test "multiple 2-element tuples in same function" do
      source = """
      defmodule Example do
        def process(val) do
          if val > 0 do
            {:ok, val}
          else
            {:error, :negative}
          end
        end
      end
      """

      assert issue_count(source) == 0
    end

    test "2-element tuples in case statement" do
      source = """
      defmodule Example do
        def handle(result) do
          case result do
            :success -> {:ok, :done}
            :failure -> {:error, :failed}
          end
        end
      end
      """

      assert issue_count(source) == 0
    end
  end

  describe "Non-result tuples of any length (no issues)" do
    test "3-element tuple not starting with :ok or :error" do
      source = """
      defmodule Example do
        def coordinates do
          {:coord, 1, 2}
        end
      end
      """

      assert issue_count(source) == 0
    end

    test "4-element tuple not starting with :ok or :error" do
      source = """
      defmodule Example do
        def data do
          {:data, :a, :b, :c}
        end
      end
      """

      assert issue_count(source) == 0
    end

    test "regular 2-element tuple" do
      source = """
      defmodule Example do
        def pair do
          {1, 2}
        end
      end
      """

      assert issue_count(source) == 0
    end

    test "regular 3-element tuple" do
      source = """
      defmodule Example do
        def triple do
          {1, 2, 3}
        end
      end
      """

      assert issue_count(source) == 0
    end
  end

  describe "Invalid 3+ element :ok tuples (should flag)" do
    test "3-element :ok tuple" do
      source = """
      defmodule Example do
        def process(data) do
          {:ok, data, :metadata}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [issue] = issues
      assert issue.message =~ "3-element :ok tuple"
      assert issue.line_no == 3
    end

    test "4-element :ok tuple" do
      source = """
      defmodule Example do
        def process(data) do
          {:ok, data, :meta, :extra}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [issue] = issues
      assert issue.message =~ "4-element :ok tuple"
    end

    test "5-element :ok tuple" do
      source = """
      defmodule Example do
        def process(data) do
          {:ok, :a, :b, :c, :d}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [issue] = issues
      assert issue.message =~ "5-element :ok tuple"
    end
  end

  describe "Invalid 3+ element :error tuples (should flag)" do
    test "3-element :error tuple" do
      source = """
      defmodule Example do
        def validate(data) do
          {:error, :invalid, :details}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [issue] = issues
      assert issue.message =~ "3-element :error tuple"
      assert issue.line_no == 3
    end

    test "4-element :error tuple" do
      source = """
      defmodule Example do
        def validate(data) do
          {:error, :code, :message, :context}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [issue] = issues
      assert issue.message =~ "4-element :error tuple"
    end

    test "6-element :error tuple" do
      source = """
      defmodule Example do
        def fail do
          {:error, :a, :b, :c, :d, :e}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 1
      [issue] = issues
      assert issue.message =~ "6-element :error tuple"
    end
  end

  describe "Tuples in various contexts (all should flag if 3+ elements)" do
    test "in function return" do
      source = """
      defmodule Example do
        def process(data) do
          {:ok, data, :meta}
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "in variable assignment" do
      source = """
      defmodule Example do
        def process(data) do
          result = {:ok, data, :meta}
          result
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "in case pattern match" do
      source = """
      defmodule Example do
        def handle(result) do
          case result do
            {:ok, val, meta} -> val
            _ -> nil
          end
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "in function argument" do
      source = """
      defmodule Example do
        def process do
          handle({:ok, :data, :meta})
        end

        defp handle(_), do: :ok
      end
      """

      assert issue_count(source) == 1
    end

    test "in list literal" do
      source = """
      defmodule Example do
        def results do
          [{:ok, :a, :meta}, {:error, :b}]
        end
      end
      """

      # Should flag the first tuple only
      assert issue_count(source) == 1
    end

    test "in map value" do
      source = """
      defmodule Example do
        def results do
          %{result: {:ok, :data, :meta}}
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "in if statement" do
      source = """
      defmodule Example do
        def process(val) do
          if val > 0 do
            {:ok, val, :positive}
          else
            {:error, :negative}
          end
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "in cond statement" do
      source = """
      defmodule Example do
        def classify(val) do
          cond do
            val > 10 -> {:ok, :high, :meta}
            val > 0 -> {:ok, :low}
            true -> {:error, :negative}
          end
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "in with statement" do
      source = """
      defmodule Example do
        def process(data) do
          with {:ok, x} <- step1(data) do
            {:ok, x, :metadata}
          end
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "in try-rescue block" do
      source = """
      defmodule Example do
        def safe_process(data) do
          try do
            {:ok, process(data), :timestamp}
          rescue
            _ -> {:error, :failed}
          end
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "as function clause pattern" do
      source = """
      defmodule Example do
        def handle({:ok, val, meta}), do: val
        def handle({:error, reason}), do: reason
      end
      """

      assert issue_count(source) == 1
    end
  end

  describe "Multiple violations in one file" do
    test "flags all 3+ element tuples" do
      source = """
      defmodule Example do
        def func1 do
          {:ok, :a, :b}
        end

        def func2 do
          {:ok, :x}
        end

        def func3 do
          {:error, :y, :z}
        end

        def func4 do
          {:ok, :m, :n, :o}
        end
      end
      """

      issues = run_check(source)
      assert length(issues) == 3
      # func1 line 3, func3 line 11, func4 line 15
      assert Enum.at(issues, 0).line_no == 3
      assert Enum.at(issues, 1).line_no == 11
      assert Enum.at(issues, 2).line_no == 15
    end

    test "flags multiple violations in same function" do
      source = """
      defmodule Example do
        def process(val) do
          result1 = {:ok, :a, :b}
          result2 = {:error, :x, :y}
          {result1, result2}
        end
      end
      """

      assert issue_count(source) == 2
    end

    test "mix of valid and invalid tuples" do
      source = """
      defmodule Example do
        def mixed do
          valid1 = {:ok, :data}
          invalid1 = {:ok, :data, :meta}
          valid2 = {:error, :reason}
          invalid2 = {:error, :code, :msg}
          {valid1, invalid1, valid2, invalid2}
        end
      end
      """

      assert issue_count(source) == 2
    end
  end

  describe "Edge cases" do
    test "nested tuples" do
      source = """
      defmodule Example do
        def nested do
          {:ok, {:inner, :tuple}, :meta}
        end
      end
      """

      # Should flag the outer 3-element tuple
      assert issue_count(source) == 1
    end

    test "tuple in pipe chain" do
      source = """
      defmodule Example do
        def process(data) do
          data
          |> validate()
          |> case do
            true -> {:ok, data, :validated}
            false -> {:error, :invalid}
          end
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "empty module" do
      source = """
      defmodule Example do
      end
      """

      assert issue_count(source) == 0
    end

    test "module with no result tuples" do
      source = """
      defmodule Example do
        def add(a, b), do: a + b
        def multiply(a, b), do: a * b
      end
      """

      assert issue_count(source) == 0
    end

    test "tuple with variables" do
      source = """
      defmodule Example do
        def process(data, meta) do
          {:ok, data, meta}
        end
      end
      """

      assert issue_count(source) == 1
    end

    test "tuple with complex expressions" do
      source = """
      defmodule Example do
        def process(data) do
          {:ok, transform(data), calculate_meta(data)}
        end
      end
      """

      assert issue_count(source) == 1
    end
  end

  describe "Private functions" do
    test "flags 3+ element tuples in private functions" do
      source = """
      defmodule Example do
        defp internal(data) do
          {:ok, data, :meta}
        end
      end
      """

      assert issue_count(source) == 1
    end
  end

  describe "Issue metadata" do
    test "issue has correct check and category" do
      source = """
      defmodule Example do
        def process do
          {:ok, :a, :b}
        end
      end
      """

      [issue] = run_check(source)
      assert issue.check == TwoElementCheck
      assert issue.category == :consistency
    end

    test "issue message describes the problem" do
      source = """
      defmodule Example do
        def process do
          {:ok, :a, :b}
        end
      end
      """

      [issue] = run_check(source)
      assert issue.message =~ "3-element :ok tuple"
      assert issue.message =~ "should be exactly 2 elements"
    end
  end
end
