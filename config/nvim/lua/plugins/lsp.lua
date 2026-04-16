return {
    -- enable clangd manually
    {
        "neovim/nvim-lspconfig",
        opts = {
            servers = {
                clangd = {
                    cmd = { "clangd" },
                    -- optional flags (you can tweak these later)
                    cmd_env = {
                        -- ensure nix shell environment is passed through
                        PATH = vim.env.PATH,
                    },
                },
            },
        },
    },
}
