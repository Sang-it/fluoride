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
  abstract_class_declaration = "abstract class",
  interface_declaration = "interface",
  type_alias_declaration = "type",
  enum_declaration = "enum",
  export_statement = "export",
  expression_statement = "expression",
  ambient_declaration = "declare",
  module = "namespace",
}

-- Node types to skip entirely
local SKIP_TYPES = {
  comment = true,
  import_statement = true,
  decorator = true,
}

-- Display type prefix → highlight groups
M.highlights = {
  ["function"]                = { prefix = "Keyword",  name = "Function" },
  ["export function"]         = { prefix = "Keyword",  name = "Function" },
  ["const"]                   = { prefix = "Keyword",  name = "Identifier" },
  ["let"]                     = { prefix = "Keyword",  name = "Identifier" },
  ["var"]                     = { prefix = "Keyword",  name = "Identifier" },
  ["export const"]            = { prefix = "Keyword",  name = "Identifier" },
  ["export let"]              = { prefix = "Keyword",  name = "Identifier" },
  ["export var"]              = { prefix = "Keyword",  name = "Identifier" },
  ["class"]                   = { prefix = "Type",     name = "Type" },
  ["export class"]            = { prefix = "Type",     name = "Type" },
  ["abstract class"]          = { prefix = "Type",     name = "Type" },
  ["export abstract class"]   = { prefix = "Type",     name = "Type" },
  ["interface"]               = { prefix = "Type",     name = "Type" },
  ["export interface"]        = { prefix = "Type",     name = "Type" },
  ["type"]                    = { prefix = "Type",     name = "Type" },
  ["export type"]             = { prefix = "Type",     name = "Type" },
  ["enum"]                    = { prefix = "Type",     name = "Type" },
  ["export enum"]             = { prefix = "Type",     name = "Type" },
  ["namespace"]               = { prefix = "Type",     name = "Type" },
  ["export namespace"]        = { prefix = "Type",     name = "Type" },
  ["declare"]                 = { prefix = "Keyword",  name = "Identifier" },
  ["declare function"]        = { prefix = "Keyword",  name = "Function" },
  ["declare class"]           = { prefix = "Type",     name = "Type" },
  ["declare abstract class"]  = { prefix = "Type",     name = "Type" },
  ["declare const"]           = { prefix = "Keyword",  name = "Identifier" },
  ["declare let"]             = { prefix = "Keyword",  name = "Identifier" },
  ["declare var"]             = { prefix = "Keyword",  name = "Identifier" },
  ["declare interface"]       = { prefix = "Type",     name = "Type" },
  ["declare type"]            = { prefix = "Type",     name = "Type" },
  ["declare enum"]            = { prefix = "Type",     name = "Type" },
  ["declare namespace"]       = { prefix = "Type",     name = "Type" },
  ["export"]                  = { prefix = "Keyword",  name = "Identifier" },
  ["expression"]              = { prefix = "Keyword",  name = "Identifier" },
  ["method"]                  = { prefix = "Keyword",  name = "Function" },
  ["abstract method"]         = { prefix = "Keyword",  name = "Function" },
  ["property"]                = { prefix = "Keyword",  name = "Identifier" },
  ["member"]                  = { prefix = "Keyword",  name = "Identifier" },
  ["index"]                   = { prefix = "Keyword",  name = "Identifier" },
  ["static block"]            = { prefix = "Keyword",  name = "Identifier" },
  ["call"]                    = { prefix = "Keyword",  name = "Function" },
  ["new"]                     = { prefix = "Keyword",  name = "Function" },
  ["if"]                      = { prefix = "Keyword",  name = "Identifier" },
  ["while"]                   = { prefix = "Keyword",  name = "Identifier" },
  ["for"]                     = { prefix = "Keyword",  name = "Identifier" },
  ["switch"]                  = { prefix = "Keyword",  name = "Identifier" },
  ["try"]                     = { prefix = "Keyword",  name = "Identifier" },
  ["do"]                      = { prefix = "Keyword",  name = "Identifier" },
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

  -- For function, class, abstract class, interface, enum, type_alias, module: use the "name" field
  if node_type == "function_declaration"
    or node_type == "class_declaration"
    or node_type == "abstract_class_declaration"
    or node_type == "interface_declaration"
    or node_type == "enum_declaration"
    or node_type == "type_alias_declaration"
    or node_type == "module"
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
    -- Fallback: strip "export" / "export default" from the first line to avoid duplication
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    first_line = first_line:gsub("^export%s+default%s+", "")
    first_line = first_line:gsub("^export%s+", "")
    first_line = vim.trim(first_line)
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    if first_line == "" then first_line = "<export>" end
    return first_line
  end

  -- For ambient_declaration (declare): recurse into inner declaration
  if node_type == "ambient_declaration" then
    for child in node:iter_children() do
      local child_type = child:type()
      if DECLARATION_TYPES[child_type] and child_type ~= "ambient_declaration" then
        return M.get_name(child, bufnr)
      end
    end
    -- Fallback: strip "declare" from the first line to avoid duplication
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    first_line = first_line:gsub("^declare%s+", "")
    first_line = vim.trim(first_line)
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    if first_line == "" then first_line = "<declare>" end
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
    local keyword = node_type:match("^(%w+)_statement$") or node_type
    if first_line:sub(1, #keyword) == keyword then
      first_line = vim.trim(first_line:sub(#keyword + 1))
    end
    first_line = first_line:gsub("[{:]%s*$", "")
    first_line = vim.trim(first_line)
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    -- For statements with no condition (try, do), use a block indicator
    if first_line == "" then return "{...}" end
    return first_line
  end

  -- Class members
  if node_type == "method_definition" or node_type == "abstract_method_definition" then
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

  -- Enum members
  if node_type == "enum_assignment" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  if node_type == "property_identifier" then
    return vim.treesitter.get_node_text(node, bufnr)
  end

  -- Interface members
  if node_type == "property_signature" or node_type == "method_signature" or node_type == "function_signature" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- Index signature: [key: type]: type
  if node_type == "index_signature" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- Static block
  if node_type == "static_block" then
    return "<static>"
  end

  -- Call signature: (arg: type): return
  if node_type == "call_signature" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- Construct signature: new (arg: type): return
  if node_type == "construct_signature" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
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

--- Get the display type for a node (handles export and declare wrapping).
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

  -- ambient_declaration (declare): recurse into inner declaration
  if node_type == "ambient_declaration" then
    for child in node:iter_children() do
      local child_type = child:type()
      if DECLARATION_TYPES[child_type] and child_type ~= "ambient_declaration" then
        if child_type == "lexical_declaration" or child_type == "variable_declaration" then
          return "declare " .. get_variable_keyword(child, bufnr)
        end
        return "declare " .. DECLARATION_TYPES[child_type]
      end
    end
    return "declare"
  end

  if node_type == "lexical_declaration" or node_type == "variable_declaration" then
    return get_variable_keyword(node, bufnr)
  end

  -- Class members
  if node_type == "method_definition" then
    return "method"
  end
  if node_type == "abstract_method_definition" then
    return "abstract method"
  end
  if node_type == "public_field_definition" or node_type == "property_definition" then
    return "property"
  end

  -- Interface members
  if node_type == "method_signature" then
    return "method"
  end
  if node_type == "function_signature" then
    return "function"
  end
  if node_type == "property_signature" then
    return "property"
  end

  -- Enum members
  if node_type == "enum_assignment" or node_type == "property_identifier" then
    return "member"
  end

  -- Index, static block, call/construct signatures
  if node_type == "index_signature" then return "index" end
  if node_type == "static_block" then return "static block" end
  if node_type == "call_signature" then return "call" end
  if node_type == "construct_signature" then return "new" end

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

  -- Direct function declaration or method (including abstract)
  if node_type == "function_declaration"
    or node_type == "function"
    or node_type == "generator_function"
    or node_type == "generator_function_declaration"
    or node_type == "method_definition"
    or node_type == "abstract_method_definition"
    or node_type == "method_signature"
    or node_type == "function_signature"
    or node_type == "call_signature"
    or node_type == "construct_signature"
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

  -- For ambient_declaration (declare), recurse into inner declaration
  if node_type == "ambient_declaration" then
    for child in node:iter_children() do
      local child_type = child:type()
      if DECLARATION_TYPES[child_type] and child_type ~= "ambient_declaration" then
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
  if t == "class_declaration"
    or t == "abstract_class_declaration"
    or t == "interface_declaration"
    or t == "enum_declaration"
    or t == "module" then
    return true
  end
  -- Handle export_statement wrapping a nestable declaration
  if t == "export_statement" or t == "ambient_declaration" then
    for child in node:iter_children() do
      if M.is_nestable(child) then
        return true
      end
    end
  end
  return false
end

--- Get the body node to iterate for child declarations.
--- @param node any treesitter node
--- @return any|nil body node
function M.get_body_node(node)
  local t = node:type()
  if t == "class_declaration" or t == "abstract_class_declaration" then
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
  if t == "enum_declaration" then
    for child in node:iter_children() do
      if child:type() == "enum_body" then
        return child
      end
    end
  end
  if t == "module" then
    for child in node:iter_children() do
      if child:type() == "statement_block" then
        return child
      end
    end
  end
  -- Handle export_statement / ambient_declaration wrapping a nestable declaration
  if t == "export_statement" or t == "ambient_declaration" then
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
  -- Class members
  method_definition = true,
  abstract_method_definition = true,
  public_field_definition = true,
  property_definition = true,
  static_block = true,
  -- Interface members
  property_signature = true,
  method_signature = true,
  function_signature = true,
  call_signature = true,
  construct_signature = true,
  index_signature = true,
  -- Enum members
  enum_assignment = true,
  property_identifier = true,
}

-- For namespace/module children, we reuse top-level declaration logic
local NAMESPACE_CHILD_TYPES = {
  function_declaration = true,
  lexical_declaration = true,
  variable_declaration = true,
  class_declaration = true,
  abstract_class_declaration = true,
  interface_declaration = true,
  type_alias_declaration = true,
  enum_declaration = true,
  export_statement = true,
  expression_statement = true,
  ambient_declaration = true,
  module = true,
}

--- Check if a child node inside a nestable parent is a declaration.
--- @param node any treesitter node
--- @return boolean
function M.is_child_declaration(node)
  local t = node:type()
  return CHILD_TYPES[t] or NAMESPACE_CHILD_TYPES[t] or false
end

return M
