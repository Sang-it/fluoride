local M = {}

-- Node types we consider as reorderable code points
local DECLARATION_TYPES = {
  function_declaration = "function",
  lexical_declaration = "variable",
  variable_declaration = "variable",
  class_declaration = "class",
  interface_declaration = "interface",
  type_alias_declaration = "type",
  enum_declaration = "enum",
  export_statement = "export",
  expression_statement = "expression",
}

-- Node types we skip entirely
local SKIP_TYPES = {
  comment = true,
  import_statement = true,
}

--- Extract the identifier name from a declaration node.
--- @param node any treesitter node
--- @param bufnr number buffer handle
--- @return string name
local function get_declaration_name(node, bufnr)
  local node_type = node:type()

  -- For function, class, interface, enum, type_alias: use the "name" field
  if node_type == "function_declaration"
    or node_type == "class_declaration"
    or node_type == "interface_declaration"
    or node_type == "enum_declaration"
    or node_type == "type_alias_declaration"
  then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- For lexical_declaration / variable_declaration: find the first variable_declarator
  if node_type == "lexical_declaration" or node_type == "variable_declaration" then
    for child in node:iter_children() do
      if child:type() == "variable_declarator" then
        local name_node = child:field("name")[1]
        if name_node then
          return vim.treesitter.get_node_text(name_node, bufnr)
        end
      end
    end
  end

  -- For export_statement: look inside for the actual declaration
  if node_type == "export_statement" then
    for child in node:iter_children() do
      local child_type = child:type()
      if DECLARATION_TYPES[child_type] and child_type ~= "export_statement" then
        return get_declaration_name(child, bufnr)
      end
    end
    -- Fallback: try to find a default export or re-export
    -- e.g. "export default function foo" or "export { foo }"
    local text = vim.treesitter.get_node_text(node, bufnr)
    -- Truncate to first line for display
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- For expression_statement: try to get a meaningful name
  if node_type == "expression_statement" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  return "[unknown]"
end

--- Count the number of parameters (arity) for a function-like node.
--- Handles function_declaration, arrow_function, function, and generator_function.
--- @param node any treesitter node
--- @return number|nil arity the parameter count, or nil if not a function
local function get_arity(node)
  local node_type = node:type()

  -- Direct function declaration
  if node_type == "function_declaration"
    or node_type == "function"
    or node_type == "generator_function"
    or node_type == "generator_function_declaration"
  then
    local params = node:field("parameters")[1]
    if params then
      local count = 0
      for child in params:iter_children() do
        local ct = child:type()
        -- Count actual parameter nodes, skip punctuation (, and parentheses)
        if ct ~= "," and ct ~= "(" and ct ~= ")" then
          count = count + 1
        end
      end
      return count
    end
    return 0
  end

  -- Arrow function
  if node_type == "arrow_function" then
    local params = node:field("parameters")[1]
    if params then
      -- If params is an identifier (single param without parens), arity is 1
      if params:type() == "identifier" then
        return 1
      end
      -- Otherwise it's a formal_parameters node
      local count = 0
      for child in params:iter_children() do
        local ct = child:type()
        if ct ~= "," and ct ~= "(" and ct ~= ")" then
          count = count + 1
        end
      end
      return count
    end
    return 0
  end

  -- For lexical/variable declarations, check if the value is a function/arrow
  if node_type == "lexical_declaration" or node_type == "variable_declaration" then
    for child in node:iter_children() do
      if child:type() == "variable_declarator" then
        local value = child:field("value")[1]
        if value then
          local vt = value:type()
          if vt == "arrow_function" or vt == "function" or vt == "generator_function" then
            return get_arity(value)
          end
        end
      end
    end
    return nil -- not a function variable
  end

  -- For export_statement, recurse into the inner declaration
  if node_type == "export_statement" then
    for child in node:iter_children() do
      local child_type = child:type()
      if DECLARATION_TYPES[child_type] and child_type ~= "export_statement" then
        return get_arity(child)
      end
    end
    return nil
  end

  return nil
end

--- Extract the actual variable keyword (const, let, var) from a declaration node.
--- @param node any treesitter node
--- @param bufnr number buffer handle
--- @return string keyword "const", "let", or "var"
local function get_variable_keyword(node, bufnr)
  -- The first child of a lexical_declaration/variable_declaration is the keyword
  for child in node:iter_children() do
    local text = vim.treesitter.get_node_text(child, bufnr)
    if text == "const" or text == "let" or text == "var" then
      return text
    end
  end
  return "const" -- fallback
end

--- Get the display type for a node (handles export wrapping).
--- @param node any treesitter node
--- @param bufnr number buffer handle
--- @return string display_type
local function get_display_type(node, bufnr)
  local node_type = node:type()

  if node_type == "export_statement" then
    -- Look for the inner declaration type
    for child in node:iter_children() do
      local child_type = child:type()
      if DECLARATION_TYPES[child_type] and child_type ~= "export_statement" then
        if child_type == "lexical_declaration" or child_type == "variable_declaration" then
          return "export " .. get_variable_keyword(child, bufnr)
        end
        return "export " .. DECLARATION_TYPES[child_type]
      end
    end
    return "export"
  end

  if node_type == "lexical_declaration" or node_type == "variable_declaration" then
    return get_variable_keyword(node, bufnr)
  end

  return DECLARATION_TYPES[node_type] or node_type
end

--- Extract all top-level code points from a TypeScript buffer.
--- @param bufnr number buffer handle
--- @return table[] entries list of { name, display_type, start_row, end_row, lines }
function M.get_code_points(bufnr)
  local ft = vim.bo[bufnr].filetype
  local lang = ft == "typescriptreact" and "tsx" or "typescript"

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    vim.notify("CodePoints: failed to get treesitter parser for " .. lang, vim.log.levels.ERROR)
    return {}
  end

  local tree = parser:parse()[1]
  if not tree then
    vim.notify("CodePoints: failed to parse buffer", vim.log.levels.ERROR)
    return {}
  end

  local root = tree:root()
  local entries = {}

  for child in root:iter_children() do
    local node_type = child:type()

    -- Skip imports and comments
    if not SKIP_TYPES[node_type] then
      local sr, _, er, _ = child:range()
      local lines = vim.api.nvim_buf_get_lines(bufnr, sr, er + 1, false)
      local name = get_declaration_name(child, bufnr)
      local display_type = get_display_type(child, bufnr)

      local arity = get_arity(child)

      table.insert(entries, {
        name = name,
        display_type = display_type,
        arity = arity,
        start_row = sr,
        end_row = er,
        lines = lines,
      })
    end
  end

  return entries
end

return M
