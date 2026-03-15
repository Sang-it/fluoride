local M = {}

M.filetypes = { "c", "cpp" }

M.parsers = {
  c = "c",
  cpp = "cpp",
}

local SKIP_TYPES = {
  comment = true,
  preproc_include = true,
  preproc_ifdef = true,
  preproc_ifndef = true,
  preproc_if = true,
  preproc_else = true,
  preproc_endif = true,
  preproc_call = true,
  linkage_specification = true, -- extern "C" { ... }
  empty_declaration = true,     -- standalone ;
  empty_statement = true,       -- standalone ;
  [";"] = true,                 -- standalone ;
}

M.highlights = {
  ["function"]  = { prefix = "Keyword",  name = "Function" },
  ["struct"]    = { prefix = "Type",     name = "Type" },
  ["enum"]      = { prefix = "Type",     name = "Type" },
  ["union"]     = { prefix = "Type",     name = "Type" },
  ["typedef"]   = { prefix = "Type",     name = "Type" },
  ["variable"]  = { prefix = "Keyword",  name = "Identifier" },
  ["#define"]   = { prefix = "PreProc",  name = "Identifier" },
  -- C++ additions
  ["class"]     = { prefix = "Type",     name = "Type" },
  ["namespace"] = { prefix = "Keyword",  name = "Identifier" },
  ["template"]  = { prefix = "Keyword",  name = "Function" },
}

function M.is_declaration(node)
  return not SKIP_TYPES[node:type()]
end

function M.get_name(node, bufnr)
  local node_type = node:type()

  -- function_definition: int foo(int x) { ... }
  if node_type == "function_definition" then
    local declarator = node:field("declarator")[1]
    if declarator then
      -- The declarator is a function_declarator containing the name
      if declarator:type() == "function_declarator" then
        local name_decl = declarator:field("declarator")[1]
        if name_decl then
          return vim.treesitter.get_node_text(name_decl, bufnr)
        end
      -- Pointer declarator: int *foo() { ... }
      elseif declarator:type() == "pointer_declarator" then
        for child in declarator:iter_children() do
          if child:type() == "function_declarator" then
            local name_decl = child:field("declarator")[1]
            if name_decl then
              return vim.treesitter.get_node_text(name_decl, bufnr)
            end
          end
        end
      end
      return vim.treesitter.get_node_text(declarator, bufnr):match("^(%w+)")
    end
  end

  -- declaration: int x = 5; or void foo(void); or enum Foo { ... };
  if node_type == "declaration" then
    local declarator = node:field("declarator")[1]
    if declarator then
      -- Could be init_declarator, function_declarator, etc.
      if declarator:type() == "init_declarator" then
        local inner = declarator:field("declarator")[1]
        if inner then
          return vim.treesitter.get_node_text(inner, bufnr):match("^[%*]*(%w+)")
        end
      elseif declarator:type() == "function_declarator" then
        local inner = declarator:field("declarator")[1]
        if inner then
          return vim.treesitter.get_node_text(inner, bufnr)
        end
      end
      local text = vim.treesitter.get_node_text(declarator, bufnr)
      return text:match("^[%*]*(%w+)") or text
    end

    -- No declarator — bare type declaration (e.g., enum SortOrder { ... };)
    -- Look at the type field for struct/enum/union specifiers
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" or ct == "enum_specifier" or ct == "union_specifier" then
        local name_node = child:field("name")[1]
        if name_node then
          return vim.treesitter.get_node_text(name_node, bufnr)
        end
      end
    end
  end

  -- type_definition (typedef)
  if node_type == "type_definition" then
    local declarator = node:field("declarator")[1]
    if declarator then
      return vim.treesitter.get_node_text(declarator, bufnr)
    end
  end

  -- preproc_def: #define FOO ...
  if node_type == "preproc_def" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- preproc_function_def: #define FOO(x) ...
  if node_type == "preproc_function_def" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- C++ class_specifier, namespace_definition, template_declaration
  if node_type == "class_specifier" or node_type == "namespace_definition" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  if node_type == "template_declaration" then
    -- Look inside for the actual declaration
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "function_definition" or ct == "declaration" or ct == "class_specifier" then
        return M.get_name(child, bufnr)
      end
    end
  end

  -- struct/enum/union specifier at top level
  if node_type == "struct_specifier" or node_type == "enum_specifier" or node_type == "union_specifier" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  return "[unknown]"
end

function M.get_display_type(node, bufnr)
  local node_type = node:type()

  if node_type == "function_definition" then
    return "function"
  end

  if node_type == "declaration" then
    -- Check if it's a function forward declaration or variable
    local declarator = node:field("declarator")[1]
    if declarator then
      if declarator:type() == "function_declarator" then
        return "function"
      end
      return "variable"
    end

    -- No declarator — bare type declaration (e.g., enum SortOrder { ... };)
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" then return "struct" end
      if ct == "enum_specifier" then return "enum" end
      if ct == "union_specifier" then return "union" end
    end
    return "variable"
  end

  if node_type == "type_definition" then
    return "typedef"
  end

  if node_type == "preproc_def" or node_type == "preproc_function_def" then
    return "#define"
  end

  if node_type == "struct_specifier" then return "struct" end
  if node_type == "enum_specifier" then return "enum" end
  if node_type == "union_specifier" then return "union" end
  if node_type == "class_specifier" then return "class" end
  if node_type == "namespace_definition" then return "namespace" end

  if node_type == "template_declaration" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "function_definition" or ct == "declaration" then
        return "template"
      end
      if ct == "class_specifier" then
        return "template"
      end
    end
    return "template"
  end

  return node_type
end

function M.get_arity(node, _bufnr)
  local node_type = node:type()

  if node_type == "function_definition" then
    local declarator = node:field("declarator")[1]
    if declarator and declarator:type() == "function_declarator" then
      local params = declarator:field("parameters")[1]
      if params then
        local count = 0
        for child in params:iter_children() do
          local ct = child:type()
          if ct == "parameter_declaration" then
            count = count + 1
          end
        end
        -- Check for void parameter: int foo(void) should be arity 0
        if count == 1 then
          for child in params:iter_children() do
            if child:type() == "parameter_declaration" then
              local text = vim.treesitter.get_node_text(child, _bufnr)
              if text:match("^%s*void%s*$") then
                return 0
              end
            end
          end
        end
        return count
      end
    end
    return 0
  end

  -- preproc_function_def: #define FOO(x, y) — has arity
  if node_type == "preproc_function_def" then
    local params = node:field("parameters")[1]
    if params then
      local count = 0
      for child in params:iter_children() do
        if child:type() == "identifier" then
          count = count + 1
        end
      end
      return count
    end
    return 0
  end

  -- template_declaration: recurse
  if node_type == "template_declaration" then
    for child in node:iter_children() do
      if child:type() == "function_definition" then
        return M.get_arity(child, _bufnr)
      end
    end
  end

  return nil
end

return M
