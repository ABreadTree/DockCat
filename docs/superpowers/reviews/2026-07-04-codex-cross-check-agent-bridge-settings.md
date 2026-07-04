# Codex Cross-Check: Claude Agent Bridge Settings Review

Source review: `docs/superpowers/reviews/2026-07-04-claude-agent-bridge-settings-review.md`

Source spec: `docs/superpowers/specs/2026-07-04-agent-bridge-settings-design.md`

## Verification Notes

- The current Xcode project has no `CODE_SIGN_ENTITLEMENTS` setting and no `.entitlements` file. The review's App Sandbox concern is not a blocker for the current build, but the spec now documents the non-sandbox assumption and the future sandbox gate.
- Existing DockCat data backup code uses `Data.write(..., options: .atomic)`, so atomic writes match the codebase's current direction.
- The project does not currently include TOML or YAML parser dependencies. For Codex TOML and Hermes YAML, line-preserving targeted patches are safer than full parse-and-serialize rewrites.
- The current local Codex config stores `notify` as an argv array, so the wrapper must preserve argv and avoid shell string concatenation.

## Findings Cross-Check

1. **App Sandbox / filesystem permissions**: Accepted with scope adjustment.
   Current DockCat is non-sandboxed, so this is not a blocker. The spec now makes the non-sandbox assumption explicit and requires user-selected access/security-scoped bookmarks if sandboxing is added later.

2. **Atomic config writes**: Accepted.
   The spec now requires validation, metadata capture, temporary sibling write, flush, atomic replacement, and conservative permissions.

3. **Concurrent writes with running agents**: Accepted with implementation boundary.
   Full third-party file locking is not realistic. The spec now requires known process detection, `needs restart` status, and abort-on-file-change between read and write.

4. **Codex notify shell injection**: Accepted.
   The spec now requires argv-preserving wrapping with a `--chain --` marker and no shell interpolation.

5. **Backups may contain secrets**: Accepted.
   The spec now states backups may contain secrets and requires owner-only directory/file permissions plus no content logging.

6. **Hook merge strategy could overwrite user hooks**: Accepted.
   The spec now requires stable DockCat markers and merge/remove-only behavior for Claude and Hermes.

7. **Disable/restore ambiguity**: Accepted.
   The spec now forbids guessing if Codex `notify` changed away from the DockCat wrapper. It must show a conflict or use explicit backup restore.

8. **macOS GUI PATH detection**: Accepted.
   The spec now requires known install locations plus login-shell `command -v` with fixed command names and a short timeout.

9. **TOML/YAML formatting loss**: Accepted.
   The spec now prefers line-preserving patching and rejects unsafe whole-file rewrites when comments/format would be lost.

10. **Port auto-fallback**: Not accepted as proposed.
    Auto-selecting another port would break installed hook URLs and make one-click integration less predictable. The spec now explicitly keeps the configured port stable, reports bind failure, and asks the user to change the port then refresh/re-enable integrations.

11. **OpenClaw migrated status based on one machine**: Accepted.
    The spec now requires a concrete migration marker plus no live `~/.openclaw` config before showing `Migrated to Hermes`.

12. **Hermes allowlist exactness**: Accepted.
    The spec now requires exact absolute helper command strings only, with no wildcard, relative, or prefix allowlisting.

13. **Test event is not end-to-end hook validation**: Accepted.
    The spec now adds manual verification through the actual installed hook/wrapper path for each enabled integration.

## Spec Changes Made

- Added non-sandbox assumption and future sandbox authorization requirement.
- Added stable port policy and rejected automatic port hopping.
- Added safe-write requirements and concurrent-change abort behavior.
- Tightened Codex notify wrapper design around argv and line-preserving TOML patching.
- Tightened Claude/Hermes hook merge and removal behavior.
- Tightened Hermes allowlist exact command matching.
- Added backup permission and secret-handling requirements.
- Added macOS GUI PATH detection guidance.
- Added OpenClaw migrated-status criteria.
- Expanded tests and manual verification.

## Remaining Design Choice

The implementation plan should decide whether the bridge helper is:

- a small shell script that only executes fixed helper commands and safely chains argv after `--`, or
- a tiny compiled helper bundled with DockCat.

The spec allows either, but the plan must preserve the no-shell-interpolation rule.
