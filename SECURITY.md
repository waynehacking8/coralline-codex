# Security policy

## Reporting a vulnerability

Please use GitHub's private security advisory flow for this repository. Do not
open a public issue containing credentials, private rollout content, filesystem
paths you consider sensitive, or an exploit that could overwrite unrelated
files.

Include the affected version/platform, a minimal reproduction, impact, and any
suggested mitigation. Maintainers will acknowledge a complete report as soon as
practical and coordinate disclosure after a fix is available.

## Security boundaries

Coralline launches the user's existing Codex executable. It does not collect or
store credentials. Account usage is requested through Codex's authenticated
app-server; Coralline does not parse `auth.json`.

Session counters come from local rollout `token_count` records. Cache and
projection files are created with owner-only permissions where the platform
supports POSIX modes. They contain usage metadata, not prompts or responses.

The optional shell/profile hook is explicitly requested, marked, backed up,
idempotent, and removable. Installers never edit Codex `config.toml` and refuse
to overwrite unrelated command paths. `--yolo` remains a Codex option with its
original security implications; Coralline only forwards it.
