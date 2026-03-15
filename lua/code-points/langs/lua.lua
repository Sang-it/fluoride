local M = {}

M.filetypes = { "lua" }

M.parsers = {
  lua = "lua",
}

local DECLARATION_TYPES = {
  function_declaration = "function",
  variable_declaration = "local",
  assignment_statement = "variable",
  function_call = "call",
}

local SKIP_TYPES = {
  comment = true,
  return_statement = true,
}

M.highlights = {
  ["function"]       = { prefix = "Keyword",  name = "Function" },
  ["local function"] = { prefix = "Keyword",  name = "Function" },
  ["local"]          = { prefix = "Keyword",  name = "Identifier" },
  ["variable"]       = { prefix = "Keyword",  name = "Identifier" },
  ["call"]           = { prefix = "Keyword",  name = "Function" },
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
    -- Check if it's a local function (has a function_definition child via assignment)
    for child in node:iter_children() do
      if child:type() == "assignment_statement" then
        -- local foo = function() ... end
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
    -- Simple local declaration: find the variable name
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

  -- For variable declarations, check if the value is a function
  if node_type == "variable_declaration" or node_type == "assignment_statement" then
    -- Look for function definition in the value
    local text = vim.treesitter.get_node_text(node, bufnr)
    if text:match("function%s*%(") then
      -- Count params by iterating deeper
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
      end
    end
    return nil
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

  return nil
end

return M
