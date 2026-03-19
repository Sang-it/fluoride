local M = {}

M.filetypes = { "javascript", "javascriptreact" }

M.parsers = {
  javascript = "javascript",
  javascriptreact = "javascript",
}

M.comment_types = { comment = true }
M.comment_prefix = "//"

local DECLARATION_TYPES = {
  function_declaration = "function",
  generator_function_declaration = "function*",
  lexical_declaration = "variable",
  variable_declaration = "variable",
  class_declaration = "class",
  export_statement = "export",
  expression_statement = "expression",
}

local SKIP_TYPES = {
  comment = true,
  import_statement = true,
  decorator = true,
}

M.highlights = {
  ["function"]         = { prefix = "Keyword",  name = "Function" },
  ["function*"]        = { prefix = "Keyword",  name = "Function" },
  ["export function"]  = { prefix = "Keyword",  name = "Function" },
  ["export function*"] = { prefix = "Keyword",  name = "Function" },
  ["const"]            = { prefix = "Keyword",  name = "Identifier" },
  ["let"]              = { prefix = "Keyword",  name = "Identifier" },
  ["var"]              = { prefix = "Keyword",  name = "Identifier" },
  ["export const"]     = { prefix = "Keyword",  name = "Identifier" },
  ["export let"]       = { prefix = "Keyword",  name = "Identifier" },
  ["export var"]       = { prefix = "Keyword",  name = "Identifier" },
  ["class"]            = { prefix = "Type",     name = "Type" },
  ["export class"]     = { prefix = "Type",     name = "Type" },
  ["export"]           = { prefix = "Keyword",  name = "Identifier" },
  ["expression"]       = { prefix = "Keyword",  name = "Identifier" },
  ["method"]           = { prefix = "Keyword",  name = "Function" },
  ["field"]            = { prefix = "Keyword",  name = "Identifier" },
  ["static block"]     = { prefix = "Keyword",  name = "Identifier" },
  ["if"]               = { prefix = "Keyword",  name = "Identifier" },
  ["while"]            = { prefix = "Keyword",  name = "Identifier" },
  ["for"]              = { prefix = "Keyword",  name = "Identifier" },
  ["switch"]           = { prefix = "Keyword",  name = "Identifier" },
  ["try"]              = { prefix = "Keyword",  name = "Identifier" },
  ["do"]               = { prefix = "Keyword",  name = "Identifier" },
}

function M.is_declaration(node)
  return not SKIP_TYPES[node:type()]
end

function M.get_name(node, bufnr)
  local node_type = node:type()

  if node_type == "function_declaration"
    or node_type == "generator_function_declaration"
    or node_type == "class_declaration"
  then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

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

  if node_type == "export_statement" then
    for child in node:iter_children() do
      local child_type = child:type()
      if DECLARATION_TYPES[child_type] and child_type ~= "export_statement" then
        return M.get_name(child, bufnr)
      end
    end
    -- Fallback: check if this is "export default"
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if first_line:match("^export%s+default%s") then
      local rest = first_line:gsub("^export%s+default%s+", "")
      rest = vim.trim(rest)
      if rest == "" or rest == "{" then
        return "default"
      end
      if #rest > 40 then
        rest = rest:sub(1, 37) .. "..."
      end
      return rest
    end
    first_line = first_line:gsub("^export%s+", "")
    first_line = vim.trim(first_line)
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    if first_line == "" then first_line = "<export>" end
    return first_line
  end

  if node_type == "expression_statement" then
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
    or node_type == "switch_statement"
    or node_type == "try_statement"
    or node_type == "do_statement"
  then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    local keyword = node_type:match("^(.+)_statement$") or node_type
    if keyword == "for_in" or keyword == "for" then keyword = "for" end
    if first_line:sub(1, #keyword) == keyword then
      first_line = vim.trim(first_line:sub(#keyword + 1))
    end
    first_line = first_line:gsub("[{:]%s*$", "")
    first_line = vim.trim(first_line)
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    if first_line == "" then return "{...}" end
    return first_line
  end

  -- Class members
  if node_type == "method_definition" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  if node_type == "field_definition" then
    local name_node = node:field("property")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- Static block
  if node_type == "static_block" then
    return "<static>"
  end

  return "[unknown]"
end

local function get_variable_keyword(node, bufnr)
  for child in node:iter_children() do
    local text = vim.treesitter.get_node_text(child, bufnr)
    if text == "const" or text == "let" or text == "var" then
      return text
    end
  end
  return "var"
end

function M.get_display_type(node, bufnr)
  local node_type = node:type()

  if node_type == "export_statement" then
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

  -- Class members
  if node_type == "method_definition" then return "method" end
  if node_type == "field_definition" then return "field" end
  if node_type == "static_block" then return "static block" end

  -- Statement types
  local STATEMENT_MAP = {
    if_statement = "if",
    while_statement = "while",
    for_statement = "for",
    for_in_statement = "for",
    switch_statement = "switch",
    try_statement = "try",
    do_statement = "do",
  }
  if STATEMENT_MAP[node_type] then
    return STATEMENT_MAP[node_type]
  end

  return DECLARATION_TYPES[node_type] or node_type
end

function M.get_arity(node, _bufnr)
  local node_type = node:type()

  if node_type == "function_declaration"
    or node_type == "generator_function_declaration"
    or node_type == "function"
    or node_type == "generator_function"
    or node_type == "method_definition"
  then
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

  if node_type == "arrow_function" then
    local params = node:field("parameters")[1]
    if params then
      if params:type() == "identifier" then
        return 1
      end
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

  if node_type == "lexical_declaration" or node_type == "variable_declaration" then
    for child in node:iter_children() do
      if child:type() == "variable_declarator" then
        local value = child:field("value")[1]
        if value then
          local vt = value:type()
          if vt == "arrow_function" or vt == "function" or vt == "generator_function" then
            return M.get_arity(value, _bufnr)
          end
        end
      end
    end
    return nil
  end

  if node_type == "export_statement" then
    for child in node:iter_children() do
      local child_type = child:type()
      if DECLARATION_TYPES[child_type] and child_type ~= "export_statement" then
        return M.get_arity(child, _bufnr)
      end
    end
    return nil
  end

  return nil
end

function M.is_nestable(node)
  local t = node:type()
  if t == "class_declaration" then
    return true
  end
  if t == "export_statement" then
    for child in node:iter_children() do
      if M.is_nestable(child) then
        return true
      end
    end
  end
  return false
end

function M.get_body_node(node)
  local t = node:type()
  if t == "class_declaration" then
    for child in node:iter_children() do
      if child:type() == "class_body" then
        return child
      end
    end
  end
  if t == "export_statement" then
    for child in node:iter_children() do
      local body = M.get_body_node(child)
      if body then
        return body
      end
    end
  end
  return nil
end

local CHILD_TYPES = {
  method_definition = true,
  field_definition = true,
  static_block = true,
}

function M.is_child_declaration(node)
  return CHILD_TYPES[node:type()] or false
end

return M
