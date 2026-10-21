-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Yank to the system clipboard (over SSH: OSC 52, see options.lua).
vim.keymap.set({ "n", "x" }, "<leader>y", '"+y', { desc = "Yank to clipboard" })
vim.keymap.set("n", "<leader>Y", '"+y$', { desc = "Yank to clipboard (to EOL)" })
