--
-- FOLD CYCLE
--

local config = require("fold-cycle.config")
local fn = vim.fn
local cmd = vim.cmd
local api = vim.api

-- holds parameters set by init()
local init_cfg = {}

-- open a branch
local function open_branch()
	cmd(init_cfg["branch_start"] .. "," .. init_cfg["branch_end"] .. " foldopen!")
end

-- determines if the fold at `line` is open
local function is_fold_closed(line)
	local folded
	if fn.foldclosed(line) == -1 then
		folded = false
	else
		folded = true
	end
	return folded
end

-- find last/first line of the current fold branch no matter if it currently folded or not
local function find_branch(line, type)
	local view = fn.winsaveview()
	-- this is going to be either first or last line of branch. remains nil if there isn't a branch
	local branch_margin_line

	local fold_is_open
	-- is the line is folded? if not, a flag is set to try to close and later reopen it
	if not is_fold_closed(line) then
		fold_is_open = true
	else
		fold_is_open = false
	end

	-- try closing fold
	if fold_is_open then
		cmd("normal! zc")
	end

	-- find first line of closed fold
	if type == "start" then
		branch_margin_line = fn.foldclosed(line)
	-- or find last line of closed fold
	elseif type == "end" then
		branch_margin_line = fn.foldclosedend(line)
	end

	-- try opening fold
	if fold_is_open then
		cmd("normal! zo")
	end

	fn.winrestview(view)
	return branch_margin_line
end

-- finds the next fold downwards
local function find_next_fold(line)
	local view = fn.winsaveview()

	cmd(tostring(line))

	local saved_t_vb = api.nvim_get_option("t_vb")
	local saved_visualbell = api.nvim_get_option("visualbell")
	api.nvim_set_option("visualbell", true)
	api.nvim_set_option("t_vb", "")

	cmd("normal! zj")

	api.nvim_set_option("t_vb", saved_t_vb)
	api.nvim_set_option("visualbell", saved_visualbell)

	local next_fold_line = fn.line(".")

	fn.winrestview(view)

	-- check if the line of the next fold is the current line
	if next_fold_line == line then
		-- set next_fold_line to nil to indicate that there is no next fold
		next_fold_line = nil
	end

	return next_fold_line
end

-- searches the branch's open folds to find their max fold level
local function find_max_open_fold_level()
	local max_fold_level = init_cfg["fold_level"]
	local line = init_cfg["branch_start"]

	-- go through the whole branch from beginning to end
	while line ~= nil and line < init_cfg["branch_end"] do
		-- check if the current line has fold level higher than max_fold_level and isn't folded
		if (fn.foldlevel(line) > max_fold_level) and not is_fold_closed(line) then
			max_fold_level = fn.foldlevel(line)
		end

		-- find the next fold
		line = find_next_fold(line)
	end
	return max_fold_level
end

-- searches the branch's closed folds to find their max fold level
local function find_max_closed_fold_level()
	local line = init_cfg["branch_start"]
	local max_fold_level = init_cfg["fold_level"]

	-- go through the whole branch from beginning to end
	while line ~= nil and line < init_cfg["branch_end"] do
		if (fn.foldlevel(line) > max_fold_level) and is_fold_closed(line) then
			max_fold_level = fn.foldlevel(line)
		end

		line = find_next_fold(line)
	end

	return max_fold_level
end

-- close all folds of a certain fold level in the branch
local function close_branch(level)
	-- start looking for branches at top of branch
	local line = init_cfg["branch_start"]

	-- go through all the branch
	while line ~= nil and line <= init_cfg["branch_end"] do
		-- if foldlevel fo current line is level currently being closed and current line isn't folded
		if (fn.foldlevel(line) == level) and not is_fold_closed(line) then
			-- then fold it
			cmd(line .. "foldclose")
		end

		-- change the line to the next fold downwards in the file
		line = find_next_fold(line)
	end
end

-- recursively closes all folds in branch
local function close_all_folds_in_branch()
	local level = init_cfg["max_open_fold_level"]
	while not is_fold_closed(init_cfg["current_line"]) do
		close_branch(level)
		level = level - 1
	end
end

local function init()
	-- line number of current line
	local init_success = false

	init_cfg["current_line"] = api.nvim_win_get_cursor(0)[1]
	-- fold level
	init_cfg["fold_level"] = fn.foldlevel(init_cfg["current_line"])

	-- if current line cannot be folded, exit
	if init_cfg["fold_level"] > 0 then
		-- true if the current line is folded
		init_cfg["current_line_folded"] = is_fold_closed(init_cfg["current_line"])

		-- beginning of branch/fold of which the current line is a part
		init_cfg["branch_start"] = find_branch(init_cfg["current_line"], "start")

		-- end of branch/fold of which the current line is a part
		init_cfg["branch_end"] = find_branch(init_cfg["current_line"], "end")

		-- if branch_end or branch_start not a fold
		if init_cfg["branch_end"] ~= nil and init_cfg["branch_start"] ~= nil then
			-- max fold level of closed folds in branch
			init_cfg["max_closed_fold_level"] = find_max_closed_fold_level()

			-- max fold level of open folds in branch
			init_cfg["max_open_fold_level"] = find_max_open_fold_level()

			-- init was successful
			init_success = true
		end
	end
	return init_success
end

local M = {}

-- close all folds in branch
M.close_all = function()
	-- if no fold at current_line, return
	if not init() then
		return
	end

	close_all_folds_in_branch()
end

-- open all folds in branch
M.open_all = function()
	-- if no fold at current_line, return
	if not init() then
		return
	end

	open_branch()
end

-- open/close all folds in branch
M.toggle_all = function()
	-- if no fold at current_line, return
	if not init() then
		return
	end

	if init_cfg["current_line_folded"] then
		open_branch()
	else
		close_all_folds_in_branch()
	end
end

-- open one level of folds in branch
M.open = function()
	-- if no fold at current_line, return
	if not init() then
		return
	end

	-- if current line is folded
	if init_cfg["current_line_folded"] then
		cmd("foldopen")
	-- if branch is completely unfolded
	elseif init_cfg["max_closed_fold_level"] == init_cfg["fold_level"] and config.close_if_max_opened then
		close_all_folds_in_branch()
	-- if current line is unfolded but branch can still be further unfolded
	else
		local line = init_cfg["branch_start"]
		while line ~= nil and line < init_cfg["branch_end"] do
			if fn.foldlevel(line) <= init_cfg["max_closed_fold_level"] and is_fold_closed(line) then
				cmd(line .. "foldopen")
			end

			line = find_next_fold(line)
		end
	end
end

-- close one level of folds in branch
M.close = function()
	-- if no fold at current_line, return
	if not init() then
		return
	end

	-- if current line is folded
	if init_cfg["current_line_folded"] and config.open_if_max_closed then
		open_branch()
	-- if there are no open folds in branch with a fold level different from current line
	elseif init_cfg["max_open_fold_level"] == init_cfg["fold_level"] then
		cmd("foldclose")
	else
		close_branch(init_cfg["max_open_fold_level"])
	end
end

return M
