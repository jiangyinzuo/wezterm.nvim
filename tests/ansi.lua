-- Run: nvim --headless -u NONE -l tests/ansi.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local ansi = require("wezterm.ansi")
local buf = vim.api.nvim_create_buf(false, true)
local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect({ actual = actual, expected = expected }))
end

local lines, spans = ansi.decode(
  "\27[1;3;4;9;38;2;18;52;86;48;5;232m彩色\27[22;23;24;29;39;49mplain\r\n"
    .. "\27[38:2::170:187:204;4:3mRGB\27[0m\n\n", buf)
equal(lines, { "彩色plain", "RGB", "" })
equal(#spans, 2)
equal(spans[1].start_col, 0)
equal(spans[1].end_col, #"彩色")
equal(spans[1].style, {
  bold = true, italic = true, underline = true, strikethrough = true,
  fg = "#123456", bg = "#080808", ctermbg = 232,
})
equal(spans[2].style, { fg = "#aabbcc", undercurl = true })

-- Palette overrides, the 256-color cube, bright colors and foreground resets.
vim.g.terminal_color_1 = "#102030"
vim.b[buf].terminal_color_9 = "#405060"
lines, spans = ansi.decode("\27[31mred\27[91mbright\27[38;5;196mcube\27[39mplain", buf)
equal(lines, { "redbrightcubeplain" })
equal(spans[1].style, { fg = "#102030", ctermfg = 1 })
equal(spans[2].style, { fg = "#405060", ctermfg = 9 })
equal(spans[3].style, { fg = "#ff0000", ctermfg = 196 })

-- OSC hyperlinks and titles are metadata; their labels remain visible.
lines = ansi.decode("\27]0;title\7\27]8;;https://example.com\27\\link\27]8;;\27\\\ttext\27(B", buf)
equal(lines, { "link\ttext" })
equal(ansi.decode("", buf), { "" })
equal(ansi.decode("a\n\n", buf), { "a", "" })

-- RGB, reverse, underline colors and styles reach actual highlight attributes.
ansi.render(buf, "plain \27[7;58:2::10:20:30;38:2:18:52:86;4:2m彩色\27[0m tail")
local marks = vim.api.nvim_buf_get_extmarks(buf,
  vim.api.nvim_create_namespace("wezterm_snapshot"), 0, -1, { details = true })
equal(#marks, 1)
equal(marks[1][2], 0)
equal(marks[1][3], #"plain ")
equal(marks[1][4].end_col, #"plain 彩色")
local hl = vim.api.nvim_get_hl(0, { name = marks[1][4].hl_group, link = false })
equal(hl.fg, 0x123456)
equal(hl.sp, 0x0a141e)
assert(hl.reverse and hl.underdouble)
print("PASS: ANSI RGB/256-color palettes, styles, resets, UTF-8 spans, hyperlinks and blank lines")
