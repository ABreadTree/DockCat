# Agent Bridge Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add DockCat settings for default-on local agent HTTP status, plus one-click local config integration for Codex, Claude Code, Hermes, and OpenClaw detection.

**Architecture:** Keep pet presentation and HTTP ingestion unchanged at the boundary, but make the server configurable through `AppSettings`. Add a focused `AgentBridge` core module for detection, helper script generation, safe backups, and format-preserving config patchers. Settings UI calls the bridge through explicit closures so SwiftUI remains a thin operational panel.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Foundation, XCTest, existing DockCat Xcode project. No third-party TOML/YAML dependency.

---

## File Structure

- Modify `DockCatApp/DockCat/Core/Settings/AppSettings.swift`
  - Add agent HTTP and per-agent bridge settings with migration defaults.
- Modify `DockCatApp/DockCat/App/DockCatApplication.swift`
  - Start/stop/restart `AgentHTTPServer` based on settings and expose agent bridge callbacks to settings.
- Modify `DockCatApp/DockCat/Core/Agent/AgentHTTPServer.swift`
  - Add status/error reporting for bind failures without changing the endpoint contract.
- Create `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeTypes.swift`
  - Agent identifiers, detection/configuration status, action results, and per-agent row models.
- Create `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeHelper.swift`
  - Generate the `dockcat-agent-event` helper script and command argv.
- Create `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeConfigPatcher.swift`
  - Pure functions for Codex TOML line patches, Claude settings JSON merge/remove, Hermes YAML hook block patches, and OpenClaw migration detection.
- Create `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeStore.swift`
  - Backup manifests, owner-only permissions, safe writes, and home-directory injection.
- Create `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeManager.swift`
  - Detection, enable/disable/test orchestration.
- Modify `DockCatApp/DockCat/UI/Settings/SettingsWindowController.swift`
  - Pass bridge state/action closures into `SettingsView`.
- Modify `DockCatApp/DockCat/UI/Settings/SettingsView.swift`
  - Add `Agents` tab with server controls and per-agent rows.
- Modify `DockCatApp/DockCat/Support/AppStrings.swift`
  - Add localized strings for the Agents settings tab.
- Create tests:
  - `DockCatApp/DockCatTests/AppSettingsAgentBridgeTests.swift`
  - `DockCatApp/DockCatTests/AgentBridgeHelperTests.swift`
  - `DockCatApp/DockCatTests/AgentBridgeConfigPatcherTests.swift`
  - `DockCatApp/DockCatTests/AgentBridgeStoreTests.swift`
  - `DockCatApp/DockCatTests/AgentHTTPServerSettingsTests.swift`

## Task 1: Settings Defaults And Server Configuration

**Files:**
- Modify: `DockCatApp/DockCat/Core/Settings/AppSettings.swift`
- Modify: `DockCatApp/DockCat/App/DockCatApplication.swift`
- Modify: `DockCatApp/DockCat/Core/Agent/AgentHTTPServer.swift`
- Test: `DockCatApp/DockCatTests/AppSettingsAgentBridgeTests.swift`
- Test: `DockCatApp/DockCatTests/AgentHTTPServerSettingsTests.swift`

- [ ] **Step 1: Write failing settings migration tests**

Create tests that decode `{}` and assert:

```swift
XCTAssertTrue(settings.agentHTTPEnabled)
XCTAssertEqual(settings.agentHTTPPort, 8765)
XCTAssertEqual(settings.agentBridge.codex.enabled, false)
XCTAssertEqual(settings.agentBridge.claudeCode.enabled, false)
XCTAssertEqual(settings.agentBridge.hermes.enabled, false)
XCTAssertEqual(settings.agentBridge.openClaw.enabled, false)
```

- [ ] **Step 2: Run RED**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -destination 'platform=macOS' test
```

Expected: tests fail because the new settings fields do not exist.

- [ ] **Step 3: Implement settings and server start policy**

Add `AgentBridgeSettings`, `AgentBridgeAgentSetting`, `agentHTTPEnabled`, `agentHTTPPort`, and default/migration decoding. Update `DockCatApplication.configureAgentHTTPServer()` to stop the server when disabled and restart when the port changes. Add bind failure status in `AgentHTTPServer`.

- [ ] **Step 4: Run GREEN**

Run the same Xcode test command. Expected: new settings tests pass.

## Task 2: Bridge Helper Generation

**Files:**
- Create: `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeHelper.swift`
- Create: `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeTypes.swift`
- Test: `DockCatApp/DockCatTests/AgentBridgeHelperTests.swift`

- [ ] **Step 1: Write failing helper tests**

Test that generated helper text:

```swift
XCTAssertTrue(script.contains("127.0.0.1"))
XCTAssertTrue(script.contains("--chain"))
XCTAssertFalse(script.contains("eval "))
XCTAssertFalse(script.contains("sh -c"))
```

Test that Codex wrapper argv preserves the previous notify argv after `--chain --`.

- [ ] **Step 2: Run RED**

Run the full Xcode test command. Expected: helper types missing.

- [ ] **Step 3: Implement helper generation**

Generate a POSIX shell helper with fixed argument parsing, stdin JSON passthrough, `curl` POST with max time, and chain execution via argv after `--chain --`. Do not use `eval` or shell interpolation for chained commands.

- [ ] **Step 4: Run GREEN**

Run the full Xcode test command. Expected: helper tests pass.

## Task 3: Config Patchers

**Files:**
- Create: `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeConfigPatcher.swift`
- Test: `DockCatApp/DockCatTests/AgentBridgeConfigPatcherTests.swift`

- [ ] **Step 1: Write failing Codex patch tests**

Assert that a TOML file with comments and `notify = [...]` returns patched text that:

```swift
XCTAssertTrue(patched.contains("# existing comment"))
XCTAssertTrue(patched.contains("dockcat-agent-event"))
XCTAssertTrue(patched.contains("--chain"))
XCTAssertTrue(restored.contains("notify = [\"old\", \"arg\"]"))
```

- [ ] **Step 2: Write failing Claude patch tests**

Assert JSON merge preserves `env`, `theme`, and existing `Stop` hooks, adds DockCat-marked hooks, and remove only removes DockCat hooks.

- [ ] **Step 3: Write failing Hermes patch tests**

Assert an empty config with `hooks_auto_accept: false` gains a `hooks:` block, existing hook entries remain, and allowlist entries are exact absolute command strings.

- [ ] **Step 4: Write failing OpenClaw detection tests**

Assert migration status requires migration reports and no live `.openclaw` config.

- [ ] **Step 5: Run RED**

Run the full Xcode test command. Expected: patcher missing.

- [ ] **Step 6: Implement patchers**

Use line-preserving string patches for Codex/Hermes. Use `JSONSerialization` for Claude settings dictionaries. Keep all mutation functions pure: input text/data plus helper path/port, output patched text/data or conflict.

- [ ] **Step 7: Run GREEN**

Run the full Xcode test command. Expected: patcher tests pass.

## Task 4: Backup Store And Safe Writes

**Files:**
- Create: `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeStore.swift`
- Test: `DockCatApp/DockCatTests/AgentBridgeStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Test that backups are created under injected app support, manifest records original path and agent, backup files are owner-only, and safe write fails when file metadata changes between read and commit.

- [ ] **Step 2: Run RED**

Run the full Xcode test command. Expected: store missing.

- [ ] **Step 3: Implement store**

Implement injected `homeURL` and `applicationSupportURL`, backup manifest JSON, owner-only permissions via `FileManager.setAttributes`, and safe write through temporary sibling file plus atomic replacement. Preserve existing permissions when they are narrower.

- [ ] **Step 4: Run GREEN**

Run the full Xcode test command. Expected: store tests pass.

## Task 5: Bridge Manager

**Files:**
- Create: `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeManager.swift`
- Modify: `DockCatApp/DockCat/Core/AgentBridge/AgentBridgeTypes.swift`
- Test: `DockCatApp/DockCatTests/AgentBridgeManagerTests.swift`

- [ ] **Step 1: Write failing manager tests**

Use temporary fixture homes and fake command locator closures. Assert detection for Codex/Claude/Hermes/OpenClaw, enable-all skips unavailable OpenClaw, and test action returns an event payload for the existing HTTP endpoint.

- [ ] **Step 2: Run RED**

Run the full Xcode test command. Expected: manager missing.

- [ ] **Step 3: Implement manager**

Wire helper install, detection, enable, disable, test event, and status summaries. Check known install locations first, then login-shell `command -v` for fixed command names.

- [ ] **Step 4: Run GREEN**

Run the full Xcode test command. Expected: manager tests pass.

## Task 6: Settings UI

**Files:**
- Modify: `DockCatApp/DockCat/UI/Settings/SettingsView.swift`
- Modify: `DockCatApp/DockCat/UI/Settings/SettingsWindowController.swift`
- Modify: `DockCatApp/DockCat/Support/AppStrings.swift`

- [ ] **Step 1: Add strings**

Add localized labels for Agents tab, server enabled, port, server status, enable all detected, refresh, send test event, detected/not installed/migrated/enabled/failed/needs restart.

- [ ] **Step 2: Add callbacks**

Extend `SettingsView` and `SettingsWindowController` with bridge snapshot and actions: refresh, enable all, enable agent, disable agent, test agent/server.

- [ ] **Step 3: Build UI**

Add a compact `agentsTab` to `TabView` with fixed-width rows. Use toggles, text fields/steppers for port, and normal buttons for actions. Keep the window usable without nested card-on-card layouts.

- [ ] **Step 4: Verify build**

Run:

```bash
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat -configuration Debug -destination 'platform=macOS' test
```

Expected: all tests pass.

## Task 7: Manual Verification, Packaging, And Merge

**Files:**
- Modify if needed: `README.md`, `README.en.md`
- Use: `PackUp.command`

- [ ] **Step 1: Full test suite**

Run the full macOS Xcode test suite and confirm it passes.

- [ ] **Step 2: Package**

Run:

```bash
./PackUp.command
```

Expected: `DockCat.zip` is regenerated without debug/test artifacts.

- [ ] **Step 3: Local install/run**

Install into `LocalInstall/DockCat.app`, launch it, confirm Xiaohou is default, open settings, verify the Agents tab, and send `POST /agent-events` smoke events.

- [ ] **Step 4: Git integration**

Commit implementation, switch to local `main`, merge `codex-agent-http-pet-status`, and verify remote configuration only tracks the user's fork remote.
