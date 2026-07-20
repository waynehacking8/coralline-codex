# Quality gates

Version 0.2 targets a shareable 9/10 standard in each area below. A 10/10 score
is intentionally reserved for long-term field data across many real terminals
and future Codex releases.

| Area | Target | Evidence required before release |
|---|---:|---|
| Usage correctness | 9/10 | Official app-server fixture, weekly-window classification, exact reset, transient-failure retention, stale marker |
| Token tracking | 9/10 | Snake/camel event forms, incremental JSONL, partial line, process-tree discovery, session rollover |
| Projection honesty | 9/10 | Five-minute minimum baseline, warming/idle/reset-safe/tracking states, deterministic synthetic rates |
| Responsive rendering | 9/10 | Nine themes, four styles, paths with spaces, 30-column critical-value preservation |
| Onboarding | 9/10 | Visual wizard, strict validation, previews, managed shell hook, explicit bypass |
| Update safety | 9/10 | Byte-identical runtime backup, user config preservation, release highlights, idempotent hooks |
| Uninstall safety | 9/10 | Scoped removal, recoverable backups, unrelated profile/config preservation |
| macOS support | 9/10 | Hosted macOS run using Homebrew Bash, Python, tmux, Git, and ShellCheck |
| Windows support | 9/10 | Native PowerShell lifecycle plus Windows Git Bash compatibility run; honest WSL/full vs native tier |
| Shareability | 9/10 | English/Traditional Chinese docs, deterministic assets, license/notice, contribution and security policies |

## Local release checks

Run from the repository root:

```bash
bash -n bin/coralline-codex configure.sh install.sh lib/render.sh test/run.sh
python3 -m py_compile lib/*.py tools/*.py
shellcheck bin/coralline-codex configure.sh install.sh lib/render.sh test/run.sh test/verify-install.sh
./test/run.sh
python3 tools/render_assets.py --check
git diff --check
```

Run the PowerShell lifecycle on Windows:

```powershell
pwsh -NoProfile -File .\test\windows.ps1
```

Release only after all three hosted jobs—Linux, macOS, and Windows—complete
successfully on the exact commit being tagged.
