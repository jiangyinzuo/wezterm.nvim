-- Run from the repository root: nvim --headless -u NONE -l tests/spawn.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local wezterm = require("wezterm")
local job, output, exit_code
local function await_output(text)
  assert(vim.wait(5000, function()
    return output:find(text, 1, true) ~= nil
  end, 10), output)
end

-- Use a real PTY shell in place of the WezTerm transport.
wezterm.spawn = function(program, opts)
  output, exit_code = "", nil
  local argv = { program }
  vim.list_extend(argv, opts.args)
  job = vim.fn.jobstart(argv, {
    pty = true,
    on_stdout = function(_, data)
      output = output .. table.concat(data, "\n")
    end,
    on_exit = function(_, code)
      exit_code = code
    end,
  })
  assert(job > 0, "Failed to start the PTY task")
end
assert(wezterm.setup({ hold_on_exit = true }))

local function close_task()
  assert(exit_code == nil, output)
  vim.fn.chansend(job, "\n")
  assert(vim.wait(5000, function() return exit_code ~= nil end, 10), output)
  assert(exit_code == 0, output)
end

-- Preserve argument boundaries and literal shell metacharacters; hold failures.
vim.api.nvim_cmd({
  cmd = "WeztermSpawn",
  args = { "sh", "-c", "printf '<%s>\\n' \"$1\"; exit 7", "task", "hello world;$HOME" },
}, {})
await_output("<hello world;$HOME>")
await_output("[Process exited with code 7. Press Enter to close.]")
close_task()

-- With no program, use the configured shell and retain its exit status.
local shell = vim.env.SHELL
vim.env.SHELL = "/bin/sh"
vim.cmd("WeztermSpawn")
vim.fn.chansend(job, "printf 'default-shell-output\\n'; exit 9\n")
await_output("default-shell-output")
await_output("[Process exited with code 9. Press Enter to close.]")
close_task()
vim.env.SHELL = shell

-- Ctrl-C interrupts a running task without closing its output tab.
vim.api.nvim_cmd({
  cmd = "WeztermSpawn",
  args = { "sh", "-c", "printf 'task-ready\\n'; sleep 30" },
}, {})
await_output("task-ready")
vim.fn.chansend(job, "\003")
await_output("[Process exited with code 130. Press Enter to close.]")
close_task()

print("PASS: held tasks preserve arguments, exit codes and shell fallback; Enter closes cleanly; Ctrl-C retains output")
