local M = {}

M.filetypes = { "lua" }

M.parsers = {
  lua = "lua",
}

M.comment_types = { comment = true }
M.comment_prefix = "--"

local DECLARATION_TYPES = {
  function_declaration = "function",
  variable_declaration = "local",
  assignment_statement = "variable",
  function_call = "call",
}

local SKIP_TYPES = {
  comment = true,
  return_statement = true,
  empty_statement = true,
  label_statement = true,
  goto_statement = true,
}

M.highlights = {
  ["function"]       = { prefix = "Keyword",  name = "Function" },
  ["local function"] = { prefix = "Keyword",  name = "Function" },
  ["local"]          = { prefix = "Keyword",  name = "Identifier" },
  ["variable"]       = { prefix = "Keyword",  name = "Identifier" },
  ["call"]           = { prefix = "Keyword",  name = "Function" },
  ["if"]             = { prefix = "Keyword",  name = "Identifier" },
  ["while"]          = { prefix = "Keyword",  name = "Identifier" },
  ["for"]            = { prefix = "Keyword",  name = "Identifier" },
  ["do"]             = { prefix = "Keyword",  name = "Identifier" },
  ["repeat"]         = { prefix = "Keyword",  name = "Identifier" },
}

local STATEMENT_MAP = {
  if_statement = "if",
  while_statement = "while",
  for_statement = "for",
  for_in_statement = "for",
  for_numeric_statement = "for",
  for_generic_statement = "for",
  do_statement = "do",
  repeat_statement = "repeat",
}

function M.is_declaration(node)
  return not SKIP_TYPES[node:type()]
end

function M.get_name(node, bufnr)
  local node_type = node:type()

  if node_type == "function_declaration" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- local x = ... or local function foo
  if node_type == "variable_declaration" then
    for child in node:iter_children() do
      if child:type() == "assignment_statement" then
        for sub in child:iter_children() do
          if sub:type() == "variable_list" then
            local first = sub:child(0)
            if first then
              return vim.treesitter.get_node_text(first, bufnr)
            end
          end
        end
      end
    end
    -- Fallback: get first line
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- Global assignment: x = ...
  if node_type == "assignment_statement" then
    for child in node:iter_children() do
      if child:type() == "variable_list" then
        local first = child:child(0)
        if first then
          return vim.treesitter.get_node_text(first, bufnr)
        end
      end
    end
  end

  -- Top-level function call
  if node_type == "function_call" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- Statement types: extract the condition/header
  if node_type == "if_statement"
    or node_type == "while_statement"
    or node_type == "for_statement"
    or node_type == "for_in_statement"
    or node_type == "for_numeric_statement"
    or node_type == "for_generic_statement"
    or node_type == "do_statement"
    or node_type == "repeat_statement"
  then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    -- Strip leading keyword
    local keyword = first_line:match("^(%w+)")
    if keyword then
      first_line = vim.trim(first_line:sub(#keyword + 1))
    end
    -- Strip trailing "then", "do"
    first_line = first_line:gsub("%s+then%s*$", "")
    first_line = first_line:gsub("%s+do%s*$", "")
    first_line = vim.trim(first_line)
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    if first_line == "" then return "{...}" end
    return first_line
  end

  return "[unknown]"
end

function M.get_display_type(node, bufnr)
  local node_type = node:type()

  if node_type == "function_declaration" then
    -- Check if it's a local function
    local text = vim.treesitter.get_node_text(node, bufnr)
    if text:match("^local%s") then
      return "local function"
    end
    return "function"
  end

  if node_type == "variable_declaration" then
    return "local"
  end

  if STATEMENT_MAP[node_type] then
    return STATEMENT_MAP[node_type]
  end

  return DECLARATION_TYPES[node_type] or node_type
end

function M.get_arity(node, bufnr)
  local node_type = node:type()

  if node_type == "function_declaration" then
    local params = node:field("parameters")[1]
    if params then
      local count = 0
      for child in params:iter_children() do
        local ct = child:type()
        if ct ~= "," and ct ~= "(" and ct ~= ")" then
          local text = vim.treesitter.get_node_text(child, bufnr)
          -- Don't count 'self' as a parameter
          if text ~= "self" then
            count = count + 1
          end
        end
      end
      return count
    end
    return 0
  end

  -- function_definition (anonymous, used as value)
  if node_type == "function_definition" then
    local params = node:field("parameters")[1]
    if params then
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

  -- For variable declarations and assignments, check if the value is a function
  if node_type == "variable_declaration" or node_type == "assignment_statement" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    if text:match("function%s*%(") then
      for child in node:iter_children() do
        if child:type() == "assignment_statement" then
          for sub in child:iter_children() do
            if sub:type() == "expression_list" then
              for expr in sub:iter_children() do
                if expr:type() == "function_definition" then
                  return M.get_arity(expr, bufnr)
                end
              end
            end
          end
        end
        -- Direct expression_list (for assignment_statement at top level)
        if child:type() == "expression_list" then
          for expr in child:iter_children() do
            if expr:type() == "function_definition" then
              return M.get_arity(expr, bufnr)
            end
          end
        end
      end
    end
    return nil
  end

  return nil
end

-- Lua does not have nestable declaration types (no classes/structs with children)
function M.is_nestable(_node) return false end
function M.get_body_node(_node) return nil end
function M.is_child_declaration(_node) return false end

return M
