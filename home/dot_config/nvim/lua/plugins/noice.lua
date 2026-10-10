return {
  {
    "folke/noice.nvim",
    opts = {
      -- Disable cmdline UI replacement - causes nvim to exit when pressing ':'
      -- in single-file mode in regular Ghostty windows (not quake mode).
      -- This is likely a noice.nvim + Ghostty interaction bug.
      cmdline = { enabled = false },
    },
  },
}
