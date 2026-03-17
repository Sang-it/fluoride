local M = {}

M.filetypes = { "typescript", "typescriptreact" }

-- Map filetypes to treesitter parser names
M.parsers = {
  typescript = "typescript",
  typescriptreact = "tsx",
}

M.comment_types = { comment = true }
M.comment_prefix = "//"

-- Node types we consider as reorderable declarations
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

-- Node types to skip entirely
local SKIP_TYPES = {
  comment = true,
  import_statement = true,
}

-- Display type prefix → highlight groups
M.highlights = {
  ["function"]         = { prefix = "Keyword",  name = "Function" },
  ["export function"]  = { prefix = "Keyword",  name = "Function" },
  ["const"]            = { prefix = "Keyword",  name = "Identifier" },
  ["let"]              = { prefix = "Keyword",  name = "Identifier" },
  ["var"]              = { prefix = "Keyword",  name = "Identifier" },
  ["export const"]     = { prefix = "Keyword",  name = "Identifier" },
  ["export let"]       = { prefix = "Keyword",  name = "Identifier" },
  ["export var"]       = { prefix = "Keyword",  name = "Identifier" },
  ["class"]            = { prefix = "Type",     name = "Type" },
  ["export class"]     = { prefix = "Type",     name = "Type" },
  ["interface"]        = { prefix = "Type",     name = "Type" },
  ["export interface"] = { prefix = "Type",     name = "Type" },
  ["type"]             = { prefix = "Type",     name = "Type" },
  ["export type"]      = { prefix = "Type",     name = "Type" },
  ["enum"]             = { prefix = "Type",     name = "Type" },
  ["export enum"]      = { prefix = "Type",     name = "Type" },
  ["export"]           = { prefix = "Keyword",  name = "Identifier" },
  ["expression"]       = { prefix = "Keyword",  name = "Identifier" },
  ["method"]           = { prefix = "Keyword",  name = "Function" },
  ["property"]         = { prefix = "Keyword",  name = "Identifier" },
  ["if"]               = { prefix = "Keyword",  name = "Identifier" },
  ["while"]            = { prefix = "Keyword",  name = "Identifier" },
  ["for"]              = { prefix = "Keyword",  name = "Identifier" },
  ["switch"]           = { prefix = "Keyword",  name = "Identifier" },
  ["try"]              = { prefix = "Keyword",  name = "Identifier" },
  ["do"]               = { prefix = "Keyword",  name = "Identifier" },
}

--- Check if a top-level node is a code point (not a skip type).
--- @param node any treesitter node
--- @return boolean
function M.is_declaration(node)
  return not SKIP_TYPES[node:type()]
end

--- Extract the identifier name from a declaration node.
--- @param node any treesitter node
--- @param bufnr number buffer handle
--- @return string name
function M.get_name(node, bufnr)
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
        return M.get_name(child, bufnr)
      end
    end
    -- Fallback: use first line of the export statement
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- For expression_statement: use first line
  if node_type == "expression_statement" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- For statement types: extract the condition/header from the first line
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
    -- Strip the keyword from the start
    local keyword = node_type:match("^(%w+)_statement$") or node_type
    if first_line:sub(1, #keyword) == keyword then
      first_line = vim.trim(first_line:sub(#keyword + 1))
    end
    -- Strip trailing { or :
    first_line = first_line:gsub("[{:]%s*$", "")
    first_line = vim.trim(first_line)
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    if first_line == "" then return nil end
    return first_line
  end

  -- For class members: method_definition, public_field_definition, property_definition
  if node_type == "method_definition" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  if node_type == "public_field_definition" or node_type == "property_definition" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- Interface members
  if node_type == "property_signature" or node_type == "method_signature" or node_type == "function_signature" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  return "[unknown]"
end

--- Extract the actual variable keyword (const, let, var) from a declaration node.
--- @param node any treesitter node
--- @param bufnr number buffer handle
--- @return string keyword
local function get_variable_keyword(node, bufnr)
  for child in node:iter_children() do
    local text = vim.treesitter.get_node_text(child, bufnr)
    if text == "const" or text == "let" or text == "var" then
      return text
    end
  end
  return "const"
end

--- Get the display type for a node (handles export wrapping).
--- @param node any treesitter node
--- @param bufnr number buffer handle
--- @return string display_type
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
  if node_type == "method_definition" then
    return "method"
  end
  if node_type == "public_field_definition" or node_type == "property_definition" then
    return "property"
  end

  -- Interface members
  if node_type == "method_signature" or node_type == "function_signature" then
    return "method"
  end
  if node_type == "property_signature" then
    return "property"
  end

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

--- Count the number of parameters (arity) for a function-like node.
--- @param node any treesitter node
--- @param _bufnr number buffer handle (unused but part of interface)
--- @return number|nil arity
function M.get_arity(node, _bufnr)
  local node_type = node:type()

  -- Direct function declaration or method
  if node_type == "function_declaration"
    or node_type == "function"
    or node_type == "generator_function"
    or node_type == "generator_function_declaration"
    or node_type == "method_definition"
    or node_type == "method_signature"
    or node_type == "function_signature"
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

  -- Arrow function
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

  -- For lexical/variable declarations, check if the value is a function/arrow
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

  -- For export_statement, recurse into the inner declaration
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

--- Check if a node contains child declarations that can be nested.
--- @param node any treesitter node
--- @return boolean
function M.is_nestable(node)
  local t = node:type()
  return t == "class_declaration" or t == "interface_declaration"
end

--- Get the body node to iterate for child declarations.
--- @param node any treesitter node
--- @return any|nil body node
function M.get_body_node(node)
  local t = node:type()
  if t == "class_declaration" then
    for child in node:iter_children() do
      if child:type() == "class_body" then
        return child
      end
    end
  end
  if t == "interface_declaration" then
    for child in node:iter_children() do
      if child:type() == "interface_body" or child:type() == "object_type" then
        return child
      end
    end
  end
  return nil
end

local CHILD_TYPES = {
  method_definition = true,
  public_field_definition = true,
  property_definition = true,
  property_signature = true,
  method_signature = true,
  function_signature = true,
}

--- Check if a child node inside a class is a declaration.
--- @param node any treesitter node
--- @return boolean
function M.is_child_declaration(node)
  return CHILD_TYPES[node:type()] or false
end

return M
