#!/usr/bin/env python3
"""Syncs Packages/FormatWheelCore/Sources/FormatWheelCore/Resources/Localizable.xcstrings with every L("…") key
in FormatWheelCore. Keys are upstream's zh-Hans text. Existing translations are kept; TRANSLATIONS below adds
zh-Hant / en for new keys. Run after adding strings: python3 scripts/gen-strings.py"""
import json, os, re, glob
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Packages/FormatWheelCore/Sources/FormatWheelCore")
OUT = os.path.join(SRC, "Resources/Localizable.xcstrings")

# zh-Hant (Taiwan wording) and English for keys that must be translated now; the rest arrive in P4.
TRANSLATIONS = {
    "未装备": ("未裝備", "Not equipped"),
    "这个版本没有内置 FFmpeg，暂时用不了": ("這個版本沒有內建 FFmpeg，暫時無法使用", "This build doesn't include FFmpeg, so this isn't available"),
    "此设备不支持 HEIC 编码": ("此裝置不支援 HEIC 編碼", "This device can't encode HEIC"),
    "此设备不支持 AVIF 编码，也没有内置 FFmpeg": ("此裝置不支援 AVIF 編碼，也沒有內建 FFmpeg", "This device can't encode AVIF and FFmpeg isn't included"),
    "已取消": ("已取消", "Cancelled"),
    "当前": ("目前", "Current"),
    "已经是 %@ 了": ("已經是 %@ 了", "Already %@"),
}

keys = []
pattern = re.compile(r'\bL\("((?:[^"\\]|\\.)*)"')
for path in sorted(glob.glob(os.path.join(SRC, "*.swift"))):
    for m in pattern.finditer(open(path, encoding="utf-8").read()):
        k = m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8")
        if k not in keys:
            keys.append(k)

data = {"sourceLanguage": "zh-Hans", "version": "1.0", "strings": {}}
if os.path.exists(OUT):
    data = json.load(open(OUT, encoding="utf-8"))
strings = data["strings"]
for k in keys:
    entry = strings.setdefault(k, {"extractionState": "manual", "localizations": {}})
    loc = entry.setdefault("localizations", {})
    loc.setdefault("zh-Hans", {"stringUnit": {"state": "translated", "value": k}})
    if k in TRANSLATIONS:
        hant, en = TRANSLATIONS[k]
        loc["zh-Hant"] = {"stringUnit": {"state": "translated", "value": hant}}
        loc["en"] = {"stringUnit": {"state": "translated", "value": en}}
for stale in [k for k in strings if k not in keys]:
    del strings[stale]
data["strings"] = dict(sorted(strings.items()))
json.dump(data, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
done = sum(1 for v in strings.values() if "en" in v.get("localizations", {}))
print(f"{OUT}: {len(strings)} keys, {done} translated to zh-Hant/en")
