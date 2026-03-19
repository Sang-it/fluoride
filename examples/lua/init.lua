-- Fluoride Lua test file — comprehensive syntax coverage
-- Covers: function, local function, local variables, assignments,
-- function calls, control flow, do/repeat blocks

local M = {}

-- --- Module functions ---

function M.greet(name)
	return "Hello, " .. name
end

function M.add(a, b)
	return a + b
end

function M.multi_args(a, b, c, d)
	return a + b + c + d
end

-- Method-style function (with self)
function M:initialize(config)
	self.config = config
	return self
end

-- --- Local functions ---

local function helper()
	return true
end

local function validate(value, min, max)
	return value >= min and value <= max
end

local function noop() end

-- --- Local variables ---

local counter = 0

local name = "fluoride"

local config = {
	debug = false,
	timeout = 30,
	host = "localhost",
}

local items = { "a", "b", "c" }

-- --- Assignments ---

M.version = "1.0.0"

M.debug = false

M.DEFAULT_CONFIG = {
	debug = false,
	timeout = 30,
}

-- Function as variable value
local callback = function(a, b)
	return a + b
end

-- Function assigned to module
M.create = function(options)
	return setmetatable(options or {}, { __index = M })
end

-- Multiarg function as value
local transform = function(x, y, z)
	return x * y + z
end

-- --- Function calls ---

print("expression statement at top level")

io.write("direct call\n")

-- --- Control flow ---

if counter > 0 then
	print("positive")
elseif counter == 0 then
	print("zero")
else
	print("negative")
end

while counter < 10 do
	counter = counter + 1
end

for i = 1, 10 do
	local _ = i * 2
end

for k, v in pairs(config) do
	print(k, v)
end

for i, item in ipairs(items) do
	print(i, item)
end

-- --- Do block ---

do
	local temp = counter
	counter = temp + 1
end

-- --- Repeat block ---

repeat
	counter = counter - 1
until counter <= 0

-- --- Return ---

return M
