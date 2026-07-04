# Agent Bridge Settings Design

## Goal

Add a DockCat settings surface that can enable agent-to-pet status updates with one click for local agent tools. The first version covers Codex, Claude Code, Hermes, and OpenClaw detection, while keeping DockCat's HTTP endpoint loopback-only and low resource.

The selected permission model is direct configuration management: DockCat may write supported external agent config files after creating backups, and it must provide a matching disable/restore path.

This design assumes the current DockCat distribution model remains a non-sandboxed macOS app. The current Xcode project does not define app sandbox entitlements. If DockCat later enables App Sandbox or targets Mac App Store distribution, direct dotfile writes must be gated behind user-selected folder access and security-scoped bookmarks before this feature can be enabled.

## User Experience

Add an `Agents` tab to the app settings window.

Top-level controls:

- Agent HTTP server toggle, default on.
- Host display fixed to `127.0.0.1`.
- Port field, default `8765`, with validation to an available user-space port.
- Server status: running, disabled, or failed to bind.
- `Send Test Event` button that posts an `info` event to the current DockCat endpoint.
- `Enable All Detected` button that enables every supported agent found on this Mac.

If the configured port is unavailable, DockCat reports the bind failure and keeps the port value unchanged. It does not automatically hop to another port because installed agent hooks need a stable endpoint. The user can choose a different port in settings, then re-enable or refresh integrations so helper commands point at the new URL.

Per-agent rows:

- Name: Codex, Claude Code, Hermes, OpenClaw.
- Detection status: detected, not installed, migrated, unsupported, enabled, or error.
- Integration status: not configured, enabled, needs restart, or failed.
- Actions: Enable, Disable, Test.
- Short details text for the exact config file or reason the agent is unavailable.

The settings view should remain a compact operational panel. It should not become a wizard, event console, or documentation page.

## Agent Event Contract

All integrations send the existing DockCat event shape:

```json
{
  "agent": "codex",
  "session": "task-or-session-id",
  "status": "working",
  "message": "Human-readable status",
  "hint": "Bubble-friendly status"
}
```

Supported status values stay unchanged:

- `working`
- `success`
- `failure`
- `waiting`
- `info`

When an upstream tool cannot expose a precise lifecycle event, the bridge sends the closest reliable status instead of guessing. For example, Codex `notify` can reliably report turn-ended information, but cannot promise real-time per-token progress.

## Architecture

### App Settings

Extend `AppSettings` with agent integration settings:

- `agentHTTPEnabled: Bool`, default `true`.
- `agentHTTPPort: Int`, default `8765`.
- Per-agent enabled flags for Codex, Claude Code, Hermes, and OpenClaw, default `false`.

`DockCatApplication` starts, stops, or restarts `AgentHTTPServer` when these settings change. The server still binds only to `127.0.0.1`.

### Agent Integration Manager

Create a small integration layer that is separate from pet presentation:

- Detect installed agents and active config files.
- Install or update DockCat-managed config snippets.
- Create backups before first write.
- Disable DockCat snippets without removing unrelated user config.
- Report status and errors to the settings UI.
- Write config files through a shared safe-write path: parse or validate the current file, capture file metadata, write a temporary file, flush it, then atomically replace the original.
- Abort and ask the user to retry if the target config changes between read and write.
- Detect known running agent processes before enable/disable and mark integrations as `needs restart` after writing. Running processes do not block the write by themselves, but concurrent file changes do.

This manager should be testable without touching real home-directory files by injecting a base home directory and command locator.

### Bridge Helper

Install a lightweight helper script under DockCat-controlled app support storage:

```text
~/Library/Application Support/DockCat/AgentBridge/dockcat-agent-event
```

Responsibilities:

- Read optional hook payload from stdin.
- Accept command-line defaults such as `--agent`, `--status`, and `--message`.
- Extract session identifiers from known hook JSON fields when available.
- POST to `http://127.0.0.1:<port>/agent-events`.
- Use a short timeout and fail silently so agent work is never blocked by DockCat.
- When asked to chain an existing notification command, execute it as argv with no shell interpolation.

The helper must not store secrets, call remote networks, or require a resident background process.

## Agent-Specific Integration

### Codex

Codex is detected by locating `codex` on `PATH` or the configured Codex app resource path, plus `~/.codex/config.toml`.

Current reliable entry point: `notify` in `~/.codex/config.toml`.

Enable behavior:

- Back up `~/.codex/config.toml`.
- Preserve the existing `notify` command by wrapping its argv form.
- Replace `notify` with a DockCat wrapper argv that invokes the previous notify argv after a `--chain --` marker and then sends a DockCat event.
- The default Codex event maps turn completion to `success` unless the notify payload or exit metadata clearly indicates a failure or waiting state.
- Prefer a line-preserving patch for the top-level `notify` setting so comments, section order, and unrelated TOML formatting survive. Do not round-trip the whole TOML file unless a later implementation introduces a formatter-preserving TOML editor.

Disable behavior:

- If DockCat installed the wrapper, restore the previous `notify` command.
- If the file changed since enable, restore only when the current `notify` still matches the DockCat wrapper. Otherwise, show a conflict and offer backup restore instead of guessing.

Notes:

- Codex progress before the first notify event is not guaranteed in this version.
- The wrapper must preserve the current Computer Use notification behavior.

### Claude Code

Claude Code is detected by locating `claude` on `PATH` and `~/.claude/settings.json`.

Enable behavior:

- Back up `~/.claude/settings.json`.
- Add DockCat-managed command hooks directly to the user settings JSON.
- Preserve existing keys such as `env`, `theme`, and `tui`.
- Add events where supported: `SessionStart`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `Notification`, `SessionEnd`, and failure hooks if present in the installed version.
- Merge into each hook event array by a stable DockCat marker in the command arguments. Never replace a whole event array or remove non-DockCat hooks.

Status mapping:

- `SessionStart` and `UserPromptSubmit` send `working`.
- `Notification` sends `waiting` when the notification indicates user attention, otherwise `info`.
- `Stop` and `SubagentStop` send `success`.
- Failure hooks send `failure`.

Disable behavior removes only DockCat-managed hook entries.

### Hermes

Hermes is detected by locating `hermes` on `PATH` and `~/.hermes/config.yaml`.

Enable behavior:

- Back up `~/.hermes/config.yaml`.
- Ensure a `hooks:` block exists.
- Add DockCat-managed shell hooks pointing at the bridge helper.
- Merge DockCat-managed entries into existing hook event arrays without replacing unrelated hooks.
- Add or update allowlist entries only for exact absolute DockCat helper command strings if non-interactive startup needs them. No wildcards, relative paths, or prefix matches are allowed.
- Prefer a line-preserving YAML patch for the `hooks:` block where practical. If the YAML cannot be patched safely, abort with `Config parse failed` rather than rewriting the whole file and dropping user comments.

Primary shell hook events:

- `on_session_start` -> `working`
- `pre_llm_call` -> `working`
- `post_llm_call` -> `success` or `failure` when available from payload
- `subagent_stop` -> `info` or `success`
- `pre_approval_request` -> `waiting`
- `post_approval_response` -> `info`

Disable behavior removes DockCat-managed hook commands and their allowlist entries.

### OpenClaw

OpenClaw is detected by looking for an active OpenClaw executable and live config directory. On this Mac, OpenClaw appears migrated into Hermes and no active `~/.openclaw` installation is present.

Enable behavior:

- If no active OpenClaw install exists, the settings row shows `Migrated to Hermes` or `Not installed` and does not write migration archives.
- If a future active install is detected, DockCat can enable a compatibility hook only after the config schema is identified and backed up.
- `Migrated to Hermes` requires a concrete migration marker, such as a Hermes migration report under `~/.hermes/migration/openclaw/` plus no live `~/.openclaw` config directory. Otherwise the row stays `Not installed`.

The first implementation does not write into Hermes migration archives.

## Config Ownership

DockCat-managed external edits must be marked so they can be removed later.

Use explicit markers where the format allows:

- Shell scripts include a DockCat header.
- JSON hook entries include a stable command path and DockCat-specific command arguments.
- YAML hook entries use command strings rooted in the DockCat helper path.
- Codex wrapper stores its previous command in DockCat app support metadata.

Backups:

- Keep backups under DockCat app support with timestamped names.
- Store a small manifest recording original path, backup path, agent, timestamp, and integration version.
- Backup files may contain user secrets because they copy external config files. Create backup directories with owner-only permissions and set backup files to owner read/write only.
- Never include secrets or backup file contents in DockCat logs.

Restore:

- Normal disable removes DockCat snippets only.
- Restore from backup is available when snippet removal cannot safely infer the previous state.

Writes:

- Validate or parse the current config before writing.
- Capture file size, modification date, and inode/file identifier before patching.
- Write the patched content to a sibling temporary file, flush it, then atomically replace the original.
- After writing, set file permissions conservatively and avoid broadening existing permissions.

## Security And Resource Constraints

- HTTP server binds only to `127.0.0.1`.
- Default-on server is allowed, but the settings toggle can disable it.
- No polling loops for agent detection.
- Detection runs when settings opens, when refresh is clicked, or after an enable/disable operation.
- Agent executable detection must account for macOS GUI apps having a sparse `PATH`. Check known install locations first, then ask the user's login shell for `command -v <agent>` with a fixed command name and a short timeout.
- Helper uses a short timeout and no retries beyond a tiny best-effort retry for transient connection refusal.
- Helper does not block agent execution if DockCat is closed.
- External config writes are limited to supported files in the user's home directory.

## Error Handling

Settings UI should report actionable states:

- Port unavailable: server failed to bind.
- Config unreadable: show the path and permission problem.
- Config parse failed: do not write; offer backup/restore only if a prior DockCat backup exists.
- Config changed while enabling or disabling: do not write stale data; ask the user to retry after reloading status.
- Agent not found: row remains available but disabled.
- Needs restart: hook config changed, but the external agent must start a new session to load it.
- Agent running: show that the current session may not load the new hook until restart.

Failures in one agent must not prevent enabling other detected agents.

## Testing

Add focused tests for:

- `AppSettings` default migration for agent settings.
- Server start/stop decisions from settings.
- Port conflict behavior: the server reports failure without auto-selecting a different port.
- Codex config patching with an existing `notify` command.
- Codex wrapper command generation preserves the original notify argv and never shells out through string interpolation.
- Claude settings JSON patching while preserving unrelated keys.
- Claude hook merging preserves existing event arrays and removes only DockCat-marked entries.
- Hermes YAML patching for empty and existing `hooks` sections.
- Hermes allowlist writes use exact absolute commands only.
- Backup manifest creation and snippet-only disable behavior.
- Backup file permissions are owner-only.
- Safe writes abort if the target file changes between read and write.
- Bridge helper payload conversion for each supported status.
- Login-shell executable detection works when the app process `PATH` does not contain user-installed tools.

Manual verification:

- Open settings and confirm the Agents tab renders.
- Send a test event and verify Xiaohou reacts.
- Enable detected integrations on a temporary home directory fixture.
- Trigger each installed agent integration's test action and verify a DockCat event arrives through the actual installed hook or wrapper path.
- Smoke-test the real local DockCat endpoint with `curl`.
- Run the full macOS Xcode test suite before packaging.

## Out Of Scope

- Remote network agent control.
- Full event history or timeline UI.
- Custom user-defined status-to-animation mapping.
- Cloud-hosted agent sessions that cannot reach the local DockCat port.
- Guaranteed real-time token streaming status.
- Writing into OpenClaw migration archives.
