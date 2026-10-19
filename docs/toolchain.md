# Native toolchain (Windows 11, no WSL)

Docker does not run locally. Container builds, image scans and the Compose smoke
test run only in GitHub Actions. Everything else runs natively.

| Tool | Version checked | Install |
|---|---|---|
| Git for Windows (Git Bash) | 2.56.0 | already installed |
| GitHub CLI | 2.102.0 | `winget install --id GitHub.cli -e` |
| uv | 0.13.1 | `winget install --id astral-sh.uv -e` |
| Python (via uv) | 3.13.16 | `uv python install 3.13` |
| Node.js LTS | 24.20.0 | `winget install --id OpenJS.NodeJS.LTS -e` |
| OpenTofu | 1.13.1 | `winget install --id OpenTofu.Tofu -e` |
| Gitleaks | 8.30.1 | `winget install --id Gitleaks.Gitleaks -e` |
| actionlint | 1.7.12 | `winget install --id rhysd.actionlint -e` |
| just | 1.59.0 | `winget install --id Casey.Just -e` |
| pre-commit | 4.7.0 | `uv tool install pre-commit --python 3.13` |
| Hadolint | later (task 11) | not in winget; release binary |
| AWS CLI | later (task 5/6) | `winget install --id Amazon.AWSCLI -e` |

## Notes

- Restart the shell after installing, so the new PATH is picked up.
- `justfile` runs recipes in Git Bash by absolute path. A bare `bash` on PATH can
  resolve to the WSL stub in `C:\Windows\System32`, which fails without WSL.
- If you run `uv` from an MSIX-packaged app (such as the Claude desktop app),
  set `UV_PYTHON_INSTALL_DIR` and `UV_TOOL_DIR` to folders outside `AppData`.
  The app redirects `AppData` writes, and uv's Python install then fails with
  "Missing expected target directory for Python minor version link".
- Line endings: `.gitattributes` forces LF. Keep scripts LF and use forward slashes.
- Commits use the GitHub noreply address, so no personal email is in the history.
