return {
  {
    "folke/snacks.nvim",
    opts = {
      notifier = { enabled = false }, --disabling this fixed a thing where it kept crashing when trying to edit a file
      picker = {
        sources = {
          files = {
            hidden = true,
            ignored = true,
          },
          explorer = {
            hidden = true,
            ignored = true,
          },
        },
      },
    },
  },
}
