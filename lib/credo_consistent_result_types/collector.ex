defmodule CredoConsistentResultTypes.Collector do
  @moduledoc """
  Collects and analyzes return values from functions to detect inconsistent
  return type patterns.
  """

  alias Credo.SourceFile

  @doc """
  Finds all functions in a source file and returns their return values.

  Returns a list of tuples: {function_name, line_no, returns}
  where returns is a list of normalized return value patterns.

  The caller should use `categorize_returns_strict/1` or `categorize_returns_lenient/1`
  to determine if the function has inconsistent return types.
  """
  def find_inconsistent_functions(%SourceFile{} = source_file) do
    ast = SourceFile.ast(source_file)
    collect_function_returns(ast)
  end

  # Walks the AST and collects all function definitions with their return values
  defp collect_function_returns(ast) do
    {_ast, functions} =
      Macro.prewalk(ast, [], fn node, acc ->
        case node do
          # Match def and defp
          {def_type, meta, [{:when, _, [{name, _, args}, _guard]} | [body]]}
          when def_type in [:def, :defp] and is_atom(name) and is_list(args) ->
            # Body is a keyword list [do: actual_body]
            actual_body = Keyword.get(body, :do)
            returns = extract_returns(actual_body)
            function_name = "#{name}/#{length(args)}"
            {node, [{function_name, meta[:line], returns} | acc]}

          {def_type, meta, [{name, _, args} | [body]]}
          when def_type in [:def, :defp] and is_atom(name) and is_list(args) ->
            # Body is a keyword list [do: actual_body]
            actual_body = Keyword.get(body, :do)
            returns = extract_returns(actual_body)
            function_name = "#{name}/#{length(args)}"
            {node, [{function_name, meta[:line], returns} | acc]}

          # Match single-clause function heads (no body)
          {def_type, _meta, [{name, _, args}]}
          when def_type in [:def, :defp] and is_atom(name) and is_list(args) ->
            # These are function heads without body, skip them
            {node, acc}

          _ ->
            {node, acc}
        end
      end)

    functions
  end

  # Extracts all return values from a function body
  defp extract_returns(body) do
    returns = collect_return_expressions(body)

    returns
    |> Enum.uniq()
    |> Enum.reject(&(&1 == :unknown))
  end

  # Recursively collect all expressions that could be returned
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
  defp normalize_return(node) do
    case node do
      # Result tuple patterns
      :ok ->
        ":ok"

      :error ->
        ":error"

      {:ok, _} ->
        "{:ok, _}"

      {:error, _} ->
        "{:error, _}"

      # Literal values
      true ->
        "true"

      false ->
        "false"

      nil ->
        "nil"

      atom when is_atom(atom) ->
        ":#{atom}"

      num when is_number(num) ->
        "#{num}"

      str when is_binary(str) ->
        "\"...\""

      # Literal list
      list when is_list(list) and list != [] ->
        # Check if it's a keyword list (AST arg) or a literal list
        if Keyword.keyword?(list) do
          :unknown
        else
          "[...]"
        end

      [] ->
        "[]"

      # Literal tuple syntax (3+ elements)
      {:{}, _, [first | _rest]} when first in [:ok, :error] ->
        # Tuple starting with :ok or :error - normalize to show it's a result tuple
        "{:#{first}, _, ...}"

      {:{}, _, _} ->
        "{...}"

      # Map
      {:%{}, _, _} ->
        "%{...}"

      # Struct
      {:%, _, [_struct_name, {:%{}, _, _}]} ->
        "%Struct{}"

      # Two-element tuple (might be result tuple or not)
      {left, right} when not is_list(right) ->
        case left do
          :ok -> "{:ok, _}"
          :error -> "{:error, _}"
          _ -> "{_, _}"
        end

      # Function calls - try to infer from function name
      {{:., _, _}, _, _} = call ->
        infer_from_call(call)

      # AST nodes that represent function calls or other expressions
      {func_name, _, args} when is_atom(func_name) and is_list(args) ->
        infer_from_function_name(func_name)

      # Pipe operator - get the final result
      {:|>, _, [_left, right]} ->
        normalize_return(right)

      # Variable or complex expression
      _ ->
        :unknown
    end
  end

  # Try to infer return type from function call
  defp infer_from_call({{:., _, [{:__aliases__, _, _module}, func_name]}, _, _}) do
    infer_from_function_name(func_name)
  end

  defp infer_from_call(_), do: :unknown

  # Heuristic: if function name suggests result tuple, categorize as such
  defp infer_from_function_name(name) when is_atom(name) do
    name_str = Atom.to_string(name)

    cond do
      String.ends_with?(name_str, "?") -> "boolean"
      String.starts_with?(name_str, "is_") -> "boolean"
      String.starts_with?(name_str, "has_") -> "boolean"
      # These often return result tuples
      String.starts_with?(name_str, "fetch") -> :unknown
      String.starts_with?(name_str, "get") -> :unknown
      true -> :unknown
    end
  end

  defp infer_from_function_name(_), do: :unknown

  @doc """
  Categorize returns using strict rules (2-element tuples only).

  Result tuples: :ok, :error, {:ok, _}, {:error, _}
  """
  def categorize_returns_strict(returns) do
    Enum.split_with(returns, &is_result_tuple_strict?/1)
  end

  @doc """
  Categorize returns using lenient rules (any-length tuples starting with :ok or :error).

  Result tuples: :ok, :error, and any tuple starting with :ok or :error
  """
  def categorize_returns_lenient(returns) do
    Enum.split_with(returns, &is_result_tuple_lenient?/1)
  end

  # Check if a return pattern is a strict result tuple (2-element only)
  defp is_result_tuple_strict?(return) do
    case return do
      ":ok" -> true
      ":error" -> true
      "{:ok, _}" -> true
      "{:error, _}" -> true
      _ -> false
    end
  end

  # Check if a return pattern is a lenient result tuple (any length)
  defp is_result_tuple_lenient?(return) do
    case return do
      ":ok" -> true
      ":error" -> true
      # Match any tuple pattern starting with :ok or :error (any length)
      "{:ok, " <> _ -> true
      "{:error, " <> _ -> true
      _ -> false
    end
  end
end
