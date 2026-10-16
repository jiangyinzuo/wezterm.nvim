-- Run: nvim --headless -u NONE -l tests/snapshot.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect({
    actual = actual, expected = expected,
  }))
end

local notifications, reads = {}, {}
vim.notify = function(message) table.insert(notifications, message) end
local output = "\27[38:2::18:52:86m彩色 RGB\27[0m\r\n\r\nlast\r\n"
local panes = { { pane_id = 7, tab_id = 1, title = "colored logs" } }
local wezterm = {
  get_text = function(opts)
    table.insert(reads, vim.deepcopy(opts))
    return output
  end,
  list_panes = function() return panes end,
}
require("wezterm.commands").setup(wezterm)
equal(vim.fn.getcompletion("WeztermSnapshot sta", "cmdline"), {
  "start_line=",
})

local function wait_for(text)
  assert(vim.wait(2000, function()
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
      :find(text, 1, true) ~= nil
  end), "Terminal output was not rendered: " .. text)
end

local original_tab = vim.api.nvim_get_current_tabpage()
local original_win = vim.api.nvim_get_current_win()
local function close_snapshot()
  local buf = vim.api.nvim_get_current_buf()
  equal(#vim.api.nvim_list_tabpages(), 2)
  assert(vim.api.nvim_get_current_tabpage() ~= original_tab)
  equal(vim.api.nvim_tabpage_list_wins(original_tab), { original_win })
  equal(#vim.api.nvim_tabpage_list_wins(0), 1)
  equal(vim.bo[buf].buftype, "terminal")
  equal(vim.bo[buf].bufhidden, "wipe")
  assert(not vim.bo[buf].swapfile)
  assert(vim.api.nvim_buf_get_name(buf):match("^wezterm://snapshot/"))
  vim.cmd("normal q")
  assert(not vim.api.nvim_buf_is_valid(buf))
  equal(vim.api.nvim_get_current_tabpage(), original_tab)
  equal(#vim.api.nvim_list_tabpages(), 1)
end

-- TermOpen user settings must not put the snapshot in Terminal mode or hide
-- its line numbers. CRLF, CJK, colon-form RGB, and blank rows are rendered.
vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.wo.number = false
    vim.wo.relativenumber = true
    vim.cmd("startinsert")
  end,
})
vim.cmd("WeztermSnapshot pane_id=7")
equal(reads[#reads], {
  pane_id = 7, start_line = -2147483648, escapes = true,
})
wait_for("last")
equal(vim.api.nvim_buf_get_lines(0, 0, 3, false), {
  "彩色 RGB", "", "last",
})
assert(vim.wo.number and not vim.wo.relativenumber)
equal(vim.api.nvim_get_mode().mode:sub(1, 1), "n")
vim.cmd("normal! 3Gma")
vim.cmd("normal! gg")
vim.cmd("normal! 'a")
equal(vim.api.nvim_win_get_cursor(0)[1], 3)
vim.cmd("2")
equal(vim.api.nvim_win_get_cursor(0)[1], 2)
local rendered = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false))
assert(not rendered:find("\27"))
close_snapshot()

-- Retain history beyond Neovim's default 10,000 terminal scrollback lines.
local history = {}
for i = 1, 12050 do history[i] = "line " .. i end
output = table.concat(history, "\n") .. "\nEND"
vim.cmd("WeztermSnapshot pane_id=7 start_line=-15000")
wait_for("END")
equal(reads[#reads], {
  pane_id = 7, start_line = -15000, escapes = true,
})
equal(vim.api.nvim_buf_get_lines(0, 0, 1, false), { "line 1" })
equal(vim.api.nvim_buf_get_lines(0, 12049, 12051, false), {
  "line 12050", "END",
})
equal(vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_buf_line_count(0))
close_snapshot()

-- Failed reads and invalid options must leave windows unchanged.
local windows = #vim.api.nvim_list_wins()
output = nil
vim.cmd("WeztermSnapshot pane_id=999")
equal(#vim.api.nvim_list_wins(), windows)
local read_count = #reads
vim.cmd("WeztermSnapshot start_line=invalid")
equal(#reads, read_count)
assert(#notifications > 0)
output = ""
vim.cmd("WeztermSnapshot pane_id=7 start_line=0")
equal(reads[#reads], { pane_id = 7, start_line = 0, escapes = true })
equal(vim.bo.buftype, "terminal")
close_snapshot()

-- Use the shared picker, including cancellation and explicit screen capture.
package.preload["telescope.pickers"] = function() error("No Telescope") end
local choose
vim.ui.select = function(items, _, callback)
  equal(items, panes)
  choose = callback
end
read_count = #reads
vim.cmd("WeztermSnapshot")
choose(nil)
equal(#reads, read_count)
equal(#vim.api.nvim_list_wins(), windows)
output = "picked pane"
vim.cmd("WeztermSnapshot start_line=0")
choose(panes[1])
wait_for("picked pane")
equal(reads[#reads], { pane_id = 7, start_line = 0, escapes = true })
close_snapshot()

-- Attach an RGB UI to a child Neovim and inspect its rendered screen cells.
-- This verifies actual color attributes, not just stripped escape sequences.
local code = [[
  vim.opt.runtimepath:prepend(vim.fn.getcwd())
  require('wezterm.commands').setup({get_text = function()
    return '\27[38:2::18:52:86mRGB\27[0m\r\n'
  end})
  vim.cmd('WeztermSnapshot pane_id=7 start_line=0')
  assert(vim.wait(2000, function()
    return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'RGB'
  end))
  vim.cmd('redraw')
  local position = vim.fn.screenpos(0, 1, 1)
  local cell = vim.api.nvim__inspect_cell(
    1, position.row - 1, position.col - 1
  )
  vim.defer_fn(function() vim.cmd('qa!') end, 50)
  return cell
]]
local payload = vim.mpack.encode({
  0, 1, "nvim_ui_attach", { 80, 24, { rgb = true, ext_linegrid = true } },
}) .. vim.mpack.encode({ 0, 2, "nvim_exec_lua", { code, {} } })
local child = vim.system({
  vim.v.progpath, "--embed", "--headless", "-u", "NONE",
}, { stdin = true })
child:write(payload)
local result = child:wait(5000)
equal(result.code, 0)
local unpacker, position, cell = vim.mpack.Unpacker(), 1, nil
while position <= #result.stdout do
  local message
  message, position = unpacker(result.stdout, position)
  if message and message[1] == 1 and message[2] == 2 then
    equal(message[3], vim.NIL)
    cell = message[4]
  end
end
assert(cell, "No RGB UI response")
equal(cell[1], "R")
equal(cell[2].foreground, 0x123456)
print("PASS: snapshot capture, ANSI/RGB rendering, CJK, blank lines, "
  .. "large history, line jumps, marks, cleanup, and pane selection")
