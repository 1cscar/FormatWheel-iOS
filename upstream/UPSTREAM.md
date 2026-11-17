# Upstream snapshot (read-only)

This directory is an unmodified copy of the macOS app this project ports.

| | |
|---|---|
| Repository | https://github.com/Elise616/FormatWheel |
| Branch | `main` |
| Commit | `1eb19a1903ffd26ef31a183b7a8f5ea14ae7e4cc` |
| Commit date | 2026-10-21 14:39:22 +0800 |
| Commit message | 格式轮盘 FormatWheel 1.0.0 |
| License | MIT, © 2026 Elise616 (see `LICENSE`) |

Rules:

- Never edit files under `upstream/`. To update the snapshot, replace the whole directory with a newer
  commit and update this file (SHA, date) in the same commit, then diff `upstream/Sources/` to find
  what needs porting.
- `upstream/` is excluded from the Xcode project; it is reference material only.
