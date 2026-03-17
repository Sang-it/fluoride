local M = {}

M.filetypes = { "go" }

M.parsers = {
  go = "go",
}

M.comment_types = { comment = true }
M.comment_prefix = "//"

local DECLARATION_TYPES = {
  function_declaration = "func",
  method_declaration = "func",
  type_declaration = "type",
  var_declaration = "var",
  const_declaration = "const",
  short_var_declaration = "var",
}

local SKIP_TYPES = {
  comment = true,
  import_declaration = true,
  package_clause = true,
}

M.highlights = {
  ["func"]  = { prefix = "Keyword",  name = "Function" },
  ["type"]  = { prefix = "Type",     name = "Type" },
  ["var"]   = { prefix = "Keyword",  name = "Identifier" },
  ["const"] = { prefix = "Keyword",  name = "Identifier" },
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

  -- method_declaration: func (r *Receiver) MethodName(...)
  if node_type == "method_declaration" then
    local name_node = node:field("name")[1]
    if name_node then
      -- Include receiver type for clarity
      local receiver = node:field("receiver")[1]
      if receiver then
        local recv_text = vim.treesitter.get_node_text(receiver, bufnr)
        -- Extract just the type from "(r *Type)" or "(r Type)"
        local recv_type = recv_text:match("[%*]?(%w+)%s*%)") or recv_text:match("%(.-(%w+)%s*%)")
        if recv_type then
          return recv_type .. "." .. vim.treesitter.get_node_text(name_node, bufnr)
        end
      end
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- type_declaration: type Foo struct { ... }
  if node_type == "type_declaration" then
    for child in node:iter_children() do
      if child:type() == "type_spec" then
        local name_node = child:field("name")[1]
        if name_node then
          return vim.treesitter.get_node_text(name_node, bufnr)
        end
      end
    end
  end

  -- var_declaration / const_declaration
  if node_type == "var_declaration" or node_type == "const_declaration" then
    for child in node:iter_children() do
      if child:type() == "var_spec" or child:type() == "const_spec" then
        local name_node = child:field("name")[1]
        if name_node then
          return vim.treesitter.get_node_text(name_node, bufnr)
        end
      end
    end
    -- Grouped declaration: var ( ... ) — use first line
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- short_var_declaration: x := ...
  if node_type == "short_var_declaration" then
    local left = node:field("left")[1]
    if left then
      return vim.treesitter.get_node_text(left, bufnr)
    end
  end

  return "[unknown]"
end

function M.get_display_type(node, _bufnr)
  local node_type = node:type()
  return DECLARATION_TYPES[node_type] or node_type
end

function M.get_arity(node, _bufnr)
  local node_type = node:type()

  if node_type == "function_declaration" or node_type == "method_declaration" then
    local params = node:field("parameters")[1]
    if params then
      local count = 0
      for child in params:iter_children() do
        local ct = child:type()
        if ct == "parameter_declaration" then
          -- A parameter_declaration can declare multiple names: a, b int
          local names = 0
          for sub in child:iter_children() do
            if sub:type() == "identifier" then
              names = names + 1
            end
          end
          -- If no identifiers found, it's a type-only param (e.g., func(int))
          count = count + math.max(names, 1)
        end
      end
      return count
    end
    return 0
  end

  return nil
end

return M
