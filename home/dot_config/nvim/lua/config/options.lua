-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Over SSH, LazyVim leaves y/d in vim's own registers. "+y (or <leader>y) sends a yank to
-- the local clipboard via OSC 52. Pastes read vim's own register (an OSC 52 read prompts
-- in most terminals); Cmd+V pastes the system clipboard.
if vim.env.SSH_CONNECTION then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "OSC 52 (copy only)",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end
