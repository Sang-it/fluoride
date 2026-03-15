local M = {}

local DEFAULT_OPTS = {
	enabled = true,
	timeout = 5000,
	retries = 3,
}

local state = {
	initialized = false,
	count = 0,
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", DEFAULT_OPTS, opts or {})
	state.initialized = true
end

local function validate_input(input)
	if type(input) ~= "string" then
		return false, "expected string, got " .. type(input)
	end
	if #input == 0 then
		return false, "input cannot be empty"
	end
	return true, nil
end

function M.process(input)
	local ok, err = validate_input(input)
	if not ok then
		vim.notify("Error: " .. err, vim.log.levels.ERROR)
		return nil
	end

	state.count = state.count + 1

	local result = input:upper()
	return result
end

local function format_output(data)
	local lines = {}
	for k, v in pairs(data) do
		table.insert(lines, string.format("%s = %s", k, tostring(v)))
	end
	return table.concat(lines, "\n")
end

function M.get_status()
	return format_output({
		initialized = state.initialized,
		count = state.count,
		enabled = M.config and M.config.enabled or false,
	})
end

function M.reset()
	state.initialized = false
	state.count = 0
	M.config = nil
end

return M
