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
  empty_statement = true,
}

M.highlights = {
  ["func"]  = { prefix = "Keyword",  name = "Function" },
  ["type"]  = { prefix = "Type",     name = "Type" },
  ["var"]   = { prefix = "Keyword",  name = "Identifier" },
  ["const"] = { prefix = "Keyword",  name = "Identifier" },
  ["field"] = { prefix = "Keyword",  name = "Identifier" },
  ["method spec"] = { prefix = "Keyword", name = "Function" },
  ["embedded"] = { prefix = "Type",    name = "Type" },
  ["go"]    = { prefix = "Keyword",  name = "Identifier" },
  ["defer"] = { prefix = "Keyword",  name = "Identifier" },
  ["select"] = { prefix = "Keyword", name = "Identifier" },
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

  -- Struct field declarations
  if node_type == "field_declaration" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- Interface method specs
  if node_type == "method_spec" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- Embedded type in interface (e.g., io.Reader)
  if node_type == "type_identifier" or node_type == "qualified_type" then
    return vim.treesitter.get_node_text(node, bufnr)
  end

  -- Statement types
  if node_type == "go_statement"
    or node_type == "defer_statement"
    or node_type == "select_statement"
  then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    local keyword = first_line:match("^(%w+)")
    if keyword then
      first_line = vim.trim(first_line:sub(#keyword + 1))
    end
    first_line = first_line:gsub("[{]%s*$", "")
    first_line = vim.trim(first_line)
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    if first_line == "" then return nil end
    return first_line
  end

  return "[unknown]"
end

function M.get_display_type(node, _bufnr)
  local node_type = node:type()

  if node_type == "field_declaration" then return "field" end
  if node_type == "method_spec" then return "method spec" end
  if node_type == "type_identifier" or node_type == "qualified_type" then return "embedded" end
  if node_type == "go_statement" then return "go" end
  if node_type == "defer_statement" then return "defer" end
  if node_type == "select_statement" then return "select" end

  return DECLARATION_TYPES[node_type] or node_type
end

function M.get_arity(node, _bufnr)
  local node_type = node:type()

  if node_type == "function_declaration" or node_type == "method_declaration" or node_type == "method_spec" then
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

--- Check if a node contains child declarations.
function M.is_nestable(node)
  if node:type() == "type_declaration" then
    for child in node:iter_children() do
      if child:type() == "type_spec" then
        local type_node = child:field("type")[1]
        if type_node then
          local tt = type_node:type()
          if tt == "struct_type" or tt == "interface_type" then
            return true
          end
        end
      end
    end
  end
  return false
end

function M.get_body_node(node)
  if node:type() == "type_declaration" then
    for child in node:iter_children() do
      if child:type() == "type_spec" then
        local type_node = child:field("type")[1]
        if type_node then
          local tt = type_node:type()
          if tt == "struct_type" then
            for sub in type_node:iter_children() do
              if sub:type() == "field_declaration_list" then
                return sub
              end
            end
          end
          if tt == "interface_type" then
            return type_node
          end
        end
      end
    end
  end
  return nil
end

local GO_CHILD_TYPES = {
  field_declaration = true,
  method_spec = true,
  type_identifier = true,   -- embedded type in interface
  qualified_type = true,     -- embedded qualified type (e.g., io.Reader)
}

function M.is_child_declaration(node)
  return GO_CHILD_TYPES[node:type()] or false
end

return M
