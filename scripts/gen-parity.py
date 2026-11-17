#!/usr/bin/env python3
"""Regenerates docs/PARITY.md from scripts/parity_data.py and checks it covers upstream's Catalog IDs."""
import os, re, sys, collections
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
from parity_data import ACTIONS, FEATURES, CLI, NOTES

catalog = open(os.path.join(ROOT, "upstream/Sources/Catalog.swift"), encoding="utf-8").read()
ids = []
for m in re.finditer(r'(?:id: |format\(|o\(|strip\()"([a-z]+\.[a-z0-9.]+)"', catalog):
    if m.group(1) not in ids:
        ids.append(m.group(1))
mine = [a[0] for a in ACTIONS]
missing = [i for i in ids if i not in mine]
extra = [i for i in mine if i not in ids]
if missing or extra or len(set(mine)) != len(mine):
    sys.exit(f"PARITY data out of sync with upstream Catalog: missing={missing} extra={extra}")

def esc(s): return s.replace("|", "\\|")
status_count = collections.Counter(a[5] for a in ACTIONS)
out = []
out.append("# 功能對照表（PARITY）\n")
out.append("> 由 `scripts/gen-parity.py` 依 `scripts/parity_data.py` 產生，請改資料檔後重新產生。\n")
out.append("上游：Elise616/FormatWheel @ `1eb19a1`。動作 ID 以上游 `Catalog.allIDs` 為準：**%d 個**。\n" % len(ACTIONS))
out.append("狀態：⬜ 未開始 · 🟨 進行中 · ✅ 完成且有測試 · ⚠️ 有差異（見備註）\n")
out.append("動作進度：" + " · ".join(f"{k} {v}" for k, v in sorted(status_count.items())) + "\n")
out.append("## 1. 動作（%d）\n" % len(ACTIONS))
out.append("| # | ID | 類別 | 上游檔案與函式 | macOS 專屬依賴 | iOS 實作 | 狀態 | 備註 |")
out.append("|---|---|---|---|---|---|---|---|")
for n, (i, cat, up, dep, ios, st, note) in enumerate(ACTIONS, 1):
    out.append(f"| {n} | `{i}` | {cat} | {esc(up)} | {esc(dep)} | {esc(ios)} | {st} | {esc(note)} |")
out.append("\n## 2. 非動作功能（%d）\n" % len(FEATURES))
out.append("| 功能 | 上游 | iOS 實作 | 狀態 | 備註 |")
out.append("|---|---|---|---|---|")
for f, up, ios, st, note in FEATURES:
    out.append(f"| {esc(f)} | {esc(up)} | {esc(ios)} | {st} | {esc(note)} |")
out.append("\n## 3. 命令列旗標（%d）\n" % len(CLI))
out.append("上游 `main.swift` 的命令列模式在 iOS 不存在，逐一對應如下。\n")
out.append("| 旗標 | 上游行為 | iOS 對應 | 狀態 | 備註 |")
out.append("|---|---|---|---|---|")
for f, up, ios, st, note in CLI:
    out.append(f"| `{esc(f)}` | {esc(up)} | {esc(ios)} | {st} | {esc(note)} |")
out.append("\n## 4. ⚠️ 差異總表\n")
warn = [(a[0], a[6]) for a in ACTIONS if a[5] == "⚠️"] + [(f[0], f[4]) for f in FEATURES if f[3] == "⚠️"] + [(c[0], c[4]) for c in CLI if c[3] == "⚠️"]
if warn:
    for k, v in warn: out.append(f"- **{k}**：{v}")
else:
    out.append("（尚無已完成的 ⚠️ 項目；「預計 ⚠️」標在各列備註。）")
out.append("\n## 5. 替代方案說明\n")
out.append(NOTES)
open(os.path.join(ROOT, "docs/PARITY.md"), "w", encoding="utf-8").write("\n".join(out))
print(f"docs/PARITY.md: {len(ACTIONS)} actions, {len(FEATURES)} features, {len(CLI)} flags")
