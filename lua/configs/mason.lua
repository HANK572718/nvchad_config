-- Mason 確保以下工具已安裝（開啟 nvim 時若未安裝會自動下載）
return {
	ensure_installed = {
		"pyright",   -- Python LSP server（型別檢查 + 補全）
		"black",     -- Python 程式碼格式化
		"isort",     -- Python import 排序
		"debugpy",   -- Python DAP 除錯適配器
	},
}
