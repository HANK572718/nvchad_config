-- Mason 確保以下工具已安裝（開啟 nvim 時若未安裝會自動下載）
return {
  ensure_installed = {
    -- Python
    "pyright",
    "black",
    "isort",
    "debugpy",

    -- JavaScript / TypeScript
    "typescript-language-server",
    "eslint-lsp",
    "emmet-language-server",
    "tailwindcss-language-server",
    "css-lsp",
    "html-lsp",
    "json-lsp",
    "prettier",
  },
}
