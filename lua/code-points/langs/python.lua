local M = {}

M.filetypes = { "python" }

M.parsers = {
  python = "python",
}

local DECLARATION_TYPES = {
  function_definition = "def",
  class_definition = "class",
  decorated_definition = "decorated",
  assignment = "variable",
  expression_statement = "expression",
}

local SKIP_TYPES = {
  comment = true,
  import_statement = true,
  import_from_statement = true,
  future_import_statement = true,
  if_statement = true,
}

M.highlights = {
  ["def"]       = { prefix = "Keyword",  name = "Function" },
  ["async def"] = { prefix = "Keyword",  name = "Function" },
  ["class"]     = { prefix = "Type",     name = "Type" },
  ["variable"]  = { prefix = "Keyword",  name = "Identifier" },
  ["expression"] = { prefix = "Keyword", name = "Identifier" },
}

function M.is_declaration(node)
  return not SKIP_TYPES[node:type()]
end

--- Get the inner definition from a decorated_definition node.
--- @param node any treesitter node
--- @return any|nil inner the function_definition or class_definition node
local function get_inner_definition(node)
  if node:type() ~= "decorated_definition" then
    return nil
  end
  for child in node:iter_children() do
    local ct = child:type()
    if ct == "function_definition" or ct == "class_definition" then
      return child
    end
  end
  return nil
end

function M.get_name(node, bufnr)
  local node_type = node:type()

  if node_type == "function_definition" or node_type == "class_definition" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  if node_type == "decorated_definition" then
    local inner = get_inner_definition(node)
    if inner then
      return M.get_name(inner, bufnr)
    end
  end

  -- Assignment: e.g., `MAX_RETRIES = 3` or `my_list: list[int] = []`
  if node_type == "assignment" then
    local left = node:field("left")[1]
    if left then
      return vim.treesitter.get_node_text(left, bufnr)
    end
  end

  if node_type == "expression_statement" then
    -- Check if it's a typed assignment (type_alias in older Python TS grammars)
    for child in node:iter_children() do
      if child:type() == "assignment" then
        local left = child:field("left")[1]
        if left then
          return vim.treesitter.get_node_text(left, bufnr)
        end
      end
    end
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

  if node_type == "decorated_definition" then
    local inner = get_inner_definition(node)
    if inner then
      return M.get_display_type(inner, bufnr)
    end
  end

  if node_type == "function_definition" then
    -- Check if async
    local text = vim.treesitter.get_node_text(node, bufnr)
    if text:match("^async%s") then
      return "async def"
    end
    return "def"
  end

  if node_type == "class_definition" then
    return "class"
  end

  return DECLARATION_TYPES[node_type] or node_type
end

function M.get_arity(node, bufnr)
  local node_type = node:type()

  if node_type == "function_definition" then
    local params = node:field("parameters")[1]
    if params then
      local count = 0
      for child in params:iter_children() do
        local ct = child:type()
        -- Skip punctuation, 'self', and 'cls'
        if ct ~= "," and ct ~= "(" and ct ~= ")" then
          local text = vim.treesitter.get_node_text(child, bufnr)
          -- Don't count 'self' and 'cls' as parameters
          if text ~= "self" and text ~= "cls"
            and not text:match("^self:") and not text:match("^cls:") then
            count = count + 1
          end
        end
      end
      return count
    end
    return 0
  end

  if node_type == "decorated_definition" then
    local inner = get_inner_definition(node)
    if inner then
      return M.get_arity(inner, bufnr)
    end
  end

  return nil
end

return M
