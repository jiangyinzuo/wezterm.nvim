local M = {}
local namespace = vim.api.nvim_create_namespace("wezterm_snapshot")
local groups = {}
local palette = {
  "#000000", "#e00000", "#00e000", "#e0e000",
  "#0000e0", "#e000e0", "#00e0e0", "#e0e0e0",
  "#808080", "#ff4040", "#40ff40", "#ffff40",
  "#4040ff", "#ff40ff", "#40ffff", "#ffffff",
}

local function indexed_color(index, buf)
  if index < 16 then
    return vim.b[buf]["terminal_color_" .. index]
      or vim.g["terminal_color_" .. index] or palette[index + 1]
  elseif index < 232 then
    local levels = { 0, 95, 135, 175, 215, 255 }
    local value = index - 16
    return string.format("#%02x%02x%02x", levels[math.floor(value / 36) + 1],
      levels[math.floor(value / 6) % 6 + 1], levels[value % 6 + 1])
  end
  local value = 8 + (index - 232) * 10
  return string.format("#%02x%02x%02x", value, value, value)
end

local function set_color(style, key, mode, values, buf)
  if mode == 5 and values[1] and values[1] >= 0 and values[1] <= 255 then
    style[key] = indexed_color(values[1], buf)
    if key ~= "sp" then style["cterm" .. key] = values[1] end
  elseif mode == 2 and #values == 3 then
    for i = 1, 3 do
      local value = values[i]
      if type(value) ~= "number" or value < 0 or value > 255 then return end
    end
    style[key] = string.format("#%02x%02x%02x", unpack(values))
    if key ~= "sp" then style["cterm" .. key] = nil end
  end
end

local underline_keys = { "underline", "underdouble", "undercurl", "underdotted", "underdashed" }
local function underline(style, kind)
  for _, key in ipairs(underline_keys) do style[key] = nil end
  if underline_keys[kind] then style[underline_keys[kind]] = true end
end

local function sgr(parameters, style, buf)
  local tokens = vim.split(parameters, ";", { plain = true })
  local i = 1
  while i <= #tokens do
    local parts = vim.split(tokens[i], ":", { plain = true })
    local code = tonumber(parts[1]) or 0
    if code == 0 then
      style = {}
    elseif code == 1 then style.bold = true
    elseif code == 3 then style.italic = true
    elseif code == 4 then underline(style, tonumber(parts[2]) or 1)
    elseif code == 7 then style.reverse = true
    elseif code == 9 then style.strikethrough = true
    elseif code == 21 then underline(style, 2)
    elseif code == 22 then style.bold = nil
    elseif code == 23 then style.italic = nil
    elseif code == 24 then underline(style, 0)
    elseif code == 27 then style.reverse = nil
    elseif code == 29 then style.strikethrough = nil
    elseif code == 39 or code == 49 or code == 59 then
      local key = code == 39 and "fg" or code == 49 and "bg" or "sp"
      style[key] = nil
      style["cterm" .. key] = nil
    elseif (code >= 30 and code <= 37) or (code >= 90 and code <= 97)
      or (code >= 40 and code <= 47) or (code >= 100 and code <= 107) then
      local key = ((code >= 40 and code <= 47) or code >= 100) and "bg" or "fg"
      local index = code % 10 + (code >= 90 and 8 or 0)
      set_color(style, key, 5, { index }, buf)
    elseif code == 38 or code == 48 or code == 58 then
      local key = code == 38 and "fg" or code == 48 and "bg" or "sp"
      local mode, values = tonumber(parts[2]), {}
      if #parts > 1 then
        local start = mode == 2 and #parts - 2 or 3
        for j = start, #parts do values[#values + 1] = tonumber(parts[j]) end
      else
        mode = tonumber(tokens[i + 1])
        local count = mode == 2 and 3 or mode == 5 and 1 or 0
        for j = 1, count do values[j] = tonumber(tokens[i + 1 + j]) end
        i = i + 1 + count
      end
      set_color(style, key, mode, values, buf)
    end
    i = i + 1
  end
  return style
end

-- get-text --escapes exports rows with SGR styles and optional OSC hyperlinks.
-- Decode those attributes directly so window dimensions never change the text.
function M.decode(text, buf)
  local lines, spans, chunks, style = {}, {}, {}, {}
  local column, position = 0, 1
  local function append(value)
    if value == "" then return end
    chunks[#chunks + 1] = value
    if next(style) then
      spans[#spans + 1] = {
        row = #lines, start_col = column, end_col = column + #value,
        style = vim.deepcopy(style),
      }
    end
    column = column + #value
  end
  local function newline()
    lines[#lines + 1] = table.concat(chunks)
    chunks, column = {}, 0
  end
  while position <= #text do
    local first = text:find("[\27\r\n]", position)
    if not first then append(text:sub(position)); break end
    append(text:sub(position, first - 1))
    local char = text:sub(first, first)
    position = first + 1
    if char == "\n" then
      newline()
    elseif char == "\27" then
      local kind = text:sub(position, position)
      if kind == "[" then
        local start, finish, params, final = text:find("\27%[([0-?]*[ -/]*)([@-~])", first)
        if start == first then
          if final == "m" then style = sgr(params, style, buf) end
          position = finish + 1
        end
      elseif kind == "]" or kind == "P" or kind == "X" or kind == "^" or kind == "_" then
        local ending = position + 1
        while true do
          local stop = text:find("[\7\27]", ending)
          if not stop then position = #text + 1; break end
          if text:sub(stop, stop) == "\7" then position = stop + 1; break end
          if text:sub(stop + 1, stop + 1) == "\\" then position = stop + 2; break end
          ending = stop + 1
        end
      elseif kind:match("[()*+%-./]") then
        position = position + 2
      else
        position = position + 1
      end
    end
  end
  if #chunks > 0 or #lines == 0 then newline() end
  return lines, spans
end

function M.render(buf, text)
  local lines, spans = M.decode(text, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local defined = {}
  for _, span in ipairs(spans) do
    local key = vim.inspect(span.style)
    local group = groups[key]
    if not group then
      group = "WeztermSnapshot_" .. vim.fn.sha256(key):sub(1, 24)
      groups[key] = group
    end
    if not defined[group] then
      vim.api.nvim_set_hl(0, group, span.style)
      defined[group] = true
    end
    vim.api.nvim_buf_set_extmark(buf, namespace, span.row, span.start_col, {
      end_col = span.end_col, hl_group = group, priority = 100,
    })
  end
end

return M
