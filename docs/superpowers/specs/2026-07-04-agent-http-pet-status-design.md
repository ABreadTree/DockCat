# Agent HTTP Pet Status Design

## Goal

Add a lightweight local agent response channel so tools such as Codex can send status updates to DockCat, and DockCat can translate those updates into pet-specific motion and speech.

The first version prioritizes immediacy, low resource usage, and a small surface area. It is not a general automation platform, chat server, or event history system.

## Transport

DockCat starts a localhost HTTP listener by default.

- Bind address: `127.0.0.1`
- Default port: `8765`
- Endpoint: `POST /agent-events`
- Content type: `application/json`
- Request body limit: 8 KB
- Empty idle behavior: no polling, no outbound network calls

The listener accepts one event per request and returns:

- `204 No Content` for accepted events.
- `400 Bad Request` for invalid JSON, unknown status, missing required fields, or oversized body.
- `404 Not Found` for unsupported paths.
- `405 Method Not Allowed` for unsupported methods.

If the port cannot be opened, DockCat logs the failure and continues running without agent integration.

## Event Shape

Minimal JSON payload:

```json
{
  "agent": "codex",
  "session": "task-123",
  "status": "working",
  "message": "Updating tests",
  "hint": "I am checking the build now."
}
```

Fields:

- `agent`: required non-empty string, displayed in fallback messages.
- `session`: optional non-empty string. When present, DockCat uses `agent + session` to coalesce repeated low-priority updates from the same task.
- `status`: required string, one of `working`, `success`, `failure`, `waiting`, `info`.
- `message`: optional string, trimmed and capped before display.
- `hint`: optional string. When present, it is preferred as the speech bubble text.

Display text is capped to a short bubble-friendly length so a malformed or noisy client cannot create huge UI.

## Pet Actions

Selected status behavior:

| Status | Action |
| --- | --- |
| `working` | Small patrol: briefly enter a walking motion for 2-3 seconds, then return to a dialogue pose and show the working message. |
| `success` | Comfortable finish: show a dialogue success message, then switch to a random resting pose. |
| `failure` | Serious alert: switch to dialogue pose and keep the failure bubble visible longer. |
| `waiting` | Waiting for user: switch to dialogue pose and keep the bubble until the user clicks OK. |
| `info` | Turn-to-notice: switch to dialogue pose for 2-3 seconds, show the info message, then restore the previous normal state when possible. |

Fallback text:

- `working`: `"{agent} is working: {message}"`
- `success`: `"{agent} finished: {message}"`
- `failure`: `"{agent} needs attention: {message}"`
- `waiting`: `"{agent} is waiting: {message}"`
- `info`: `"{agent}: {message}"`

Chinese localization can follow the app language setting through `AppStrings`.

## Interruption Rules

Agent events must not break existing high-value DockCat interactions.

Protected interactions:

- Outing duration prompt.
- Outing departure confirmation.
- Outing return reward/event bubble.
- Recall confirmation.

Priority behavior:

- `failure` and `waiting` may interrupt resting, walking, transition, `working`, `success`, and `info` agent presentations.
- `working`, `success`, and `info` may interrupt resting and walking only.
- Protected interactions are never interrupted by agent events.
- When a low-priority event arrives during a protected interaction, DockCat keeps only the latest pending low-priority event for the same `agent + session` key and drops older low-priority events for that key.
- A high-priority `failure` or `waiting` received during a protected interaction is held as the next pending event and shown after the protected interaction finishes.
- The total pending queue is capped at five events. If it is full, DockCat drops the oldest low-priority event before dropping a high-priority event.

This keeps agent feedback visible without stealing user-driven DockCat flows.

## Components

### AgentEvent

A small Codable model for validated incoming events.

Responsibilities:

- Decode JSON.
- Validate required fields.
- Normalize status.
- Trim and cap text.

### AgentEventPresenter

A small mapper from `AgentEvent` to pet presentation instructions.

Responsibilities:

- Choose bubble text.
- Choose action kind.
- Choose duration/confirmation behavior.
- Decide priority.

### AgentHTTPServer

A thin local HTTP wrapper around Network framework primitives.

Responsibilities:

- Bind to `127.0.0.1:8765`.
- Parse minimal HTTP requests.
- Enforce request size and method/path limits.
- Deliver accepted events to the main app on the main actor.

It should not own DockCat UI state.

### DockCatApplication Integration

DockCatApplication receives accepted events and applies them through existing `CatWindowController`, `PoseRenderer`, and `CatStateMachine` patterns.

No new persistent settings are required for the first version.

## Resource Constraints

- No new package dependency.
- No event history storage.
- No polling.
- No outbound network requests.
- No background worker pool.
- No extra windows or settings UI in the first version.
- Listener binds loopback only.

## Testing

Add focused tests for:

- Valid payload decoding.
- Invalid JSON and unknown status rejection.
- Text trimming and display cap.
- Mapping each status to the selected pet action.
- Priority classification for interruption rules.

HTTP listener behavior can be covered by the smallest practical integration test if the existing Xcode test target supports it cleanly. Otherwise, the parser and presenter are the main test boundary and the listener remains a thin wrapper.

## Out Of Scope

- Agent authentication.
- Remote network access.
- Multiple endpoint versions.
- Agent event history UI.
- Custom user-configurable action mapping.
- Persistent enable/disable settings.
- New animation assets.
