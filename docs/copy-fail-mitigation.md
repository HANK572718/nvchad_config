# copy-fail-mitigation.sh — CVE-2026-31431 緩解腳本

管理 `algif_aead` kernel 模組黑名單，緩解 **Copy Fail** 本地提權漏洞。

| 項目 | 值 |
|---|---|
| CVE | CVE-2026-31431 |
| CVSS | 7.8 (High) |
| 腳本路徑 | `script/copy-fail-mitigation.sh` |
| 適用系統 | Debian / Ubuntu / Raspberry Pi OS / Jetson |
| 最後更新 | 2026-05-06 |

---

## 安裝與執行

### 方式一：從 Craft 直接下載（推薦，適用於新機器）

```bash
curl -L "https://secure-res.craft.do/v2/5M7mriV6aMWNmN9oWsaoezagGiTAmpwUDe3adbDeJ4UdyiUzb7BPBtkctHRMnphAk11PdTiRXWV3mRndHqRLR95zyawitdGFqs5doDR2nopu85NN9NxoZeAHZrYNWDdtLERPTZtzn2B1Zm3okL5G3xMdKoqWFakyjGtbvMLGoNkJAhWKGfHQEmxpP1zjPqHSnbZG1x2VyBaVJrpFmjDxCRG7VRE/copy-fail-mitigation.sh" -o copy-fail-mitigation.sh
sudo bash copy-fail-mitigation.sh
```

### 方式二：從 repo 執行

```bash
sudo bash script/copy-fail-mitigation.sh
```

**必要條件：**
- root 權限（`sudo`）
- `whiptail` 已安裝（Debian/Ubuntu 預設內建；若無：`apt install whiptail`）

---

## 功能說明

啟動後先顯示 CVE-2026-31431 漏洞說明，接著進入 TUI 主選單：

| 選項 | 說明 |
|---|---|
| 1 啟用緩解 | 寫入黑名單 + 重建 initramfs + 即時卸載模組 |
| 2 停用緩解 | 移除黑名單（取得官方 kernel 修補後才建議執行） |
| 3 查看狀態 | 顯示主機名稱、kernel 版本、模組即時狀態 |
| 4 漏洞說明 | 重新顯示 CVE 詳情 |
| 5 離開 | 結束程式 |

**預設建議：啟用緩解（選項 1）。**

---

## 漏洞背景

`algif_aead`（AF_ALG socket）與 `splice()` 系統呼叫的組合，使任意本地使用者可對 page cache 進行受控的 4-byte 寫入，竄改 setuid 二進位（如 `/usr/bin/su`）的記憶體內容，達成穩定提權至 root。PoC 為 732 bytes Python 腳本，影響 2017 年至今所有主流 Linux 發行版。

停用 `algif_aead` 對 SSH 加解密**完全無影響**（sshd 走 OpenSSL userspace，不使用 AF_ALG）。

---

## 何時可停用緩解

| 平台 | 安全 kernel 版本 |
|---|---|
| Debian Trixie（通用） | >= 6.12.85-1（已釋出） |
| Raspberry Pi RPT kernel | linux-image-rpi-v8 >= 6.12.85（尚未釋出） |
| Jetson NVIDIA L4T | 等待 NVIDIA JetPack 安全公告 |

```bash
# 確認樹莓派 kernel 版本
apt-cache policy linux-image-rpi-v8
```

---

## 參考

- Craft 完整說明文件：<https://hank.craft.me/Ys3xGR8YJZpxRS>
- [CERT-EU Advisory 2026-005](https://cert.europa.eu/publications/security-advisories/2026-005/)
- [Xint — Copy Fail 技術分析](https://xint.io/blog/copy-fail-linux-distributions)
- [BleepingComputer — CISA KEV](https://www.bleepingcomputer.com/news/security/cisa-says-copy-fail-flaw-now-exploited-to-root-linux-systems/)
