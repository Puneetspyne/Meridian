# Handoff: agents module

## Public API (MeridianAgents)

`AgentsProvider` (`@MainActor`, `SignalProvider`, providerID "agents")
- `init(settings:, supportDirectory: URL? = nil, claudeSettingsURL: URL? = nil, codex: CodexMonitor = CodexMonitor())`
- `signals: [Signal]`, `sessions: [AgentSession]` (read-only; includes dimmed `.idle` and Codex sessions)
- `dismiss(sessionID:)`, `installHooks() throws`, `uninstallHooks() throws`, `hooksStatus: HooksStatus` (`.installed/.partial/.notInstalled`), `isActive`
- Observes `Notification.Name("meridian.agents.install")` (also `AgentsProvider.installNotification`) while started and calls `installHooks()`.
- Active when `settings.agentsEnabled` and (hooks installed/partial, or `~/.codex/sessions` exists). Nothing is written to ~/.claude until `installHooks()`.

`AgentSession`: id, name, cwd, state (`.working/.needsYou/.done/.idle`), source (`.claudeCode/.codex`), lastEventAt, startedAt,
turnStartedAt, lastToolName, needsReason, needsSince, doneAt, lastTurnDuration, `actionURL` (nil for Codex). UI should show `cwd` if `claude://` has no handler.

Signal ids: `agents.session.<session id>` (Codex: `agents.session.codex-<rollout name>`).
- needsYou: `.warning`, "<name> needs you", detail = reason, value `m:ss` since needsYou, sparkles, violet, priority 70
- working: `.info`, "<name>", "Working · <tool>", value `m:ss` since turn start, sparkles, violet, priority 25 (Codex 20, "(best effort)")
- done: `.info` for 60 s then `.calm`, "<name> done", "Took 3m 12s", checkmark.circle.fill, green, priority 15
- idle: no signal.
All carry `actionURL` `claude://resume?session=<id>`, actionTitle "Open in Claude".

Other pieces: `HookScript`, `HooksInstaller`, `EventReader`, `SessionTracker`, `AgentSignals`, `CodexMonitor`. See docs/AGENTS.md for files written.

## Decisions and deviations

- Hook command is the script path alone (single-quoted only when it contains spaces, which the real path does). The script reads the event name from `hook_event_name` in the payload with parameter expansion.
- Extra events beyond the brief: PostToolUseFailure, ElicitationResult, StopFailure (treated as done; this is what the CLI emits on an API/auth failure), per the current hooks docs. Notification also matches `notification_type` in permission_prompt, idle_prompt, elicitation_dialog, elicitation_url_dialog, agent_needs_input.
- Privacy: the script stores identifier fields only. Payload keys written (when present): hook_event_name, session_id, cwd, tool_name, notification_type, stop_hook_active (bool), and for Notification events only `message` cut to 200 characters. Prompt text, tool inputs and responses, assistant replies and transcript path/contents are never written. Pure sh: parameter expansion for extraction (escape-aware for `\"` inside values), `printf '%.200s'` plus a small guard so a cut never leaves a dangling `\` or partial `\uXXXX` (which would make the line invalid JSON). No awk/sed. Assumes Claude's compact JSON (`"key":"value"`), which is what the CLI emits. The first occurrence of a key wins; common fields come first in the payload. EventReader decodes leniently so a multi-byte character cut by `printf` cannot drop an event.
- No DispatchSource watcher: 1 s Timer (tolerance 0.2) is enough.
- idle_prompt makes a finished session flip from done to needs you (per the brief's "waiting for your input" rule).
- Uninstall leaves the script and log on disk on purpose.

## Verified

- `./scripts/test.sh --scratch-path .build/agents --filter MeridianAgentsTests`: 19 tests, 5 suites, all pass (hook script run under /bin/sh including multi-line/empty/unwritable log, a leak test (prompt, tool_input, tool_response, transcript path, assistant reply absent; exact key sets per event), and message truncation at 200 incl. escaped quotes, cut mid-escape, mid-\\u escape and non-ASCII; installer merge, idempotency, uninstall, partial, invalid JSON; tracker transitions, staleness, done expiry, dismiss; reader offsets, partial lines, truncation, rotation; signal mapping; Codex scan; provider end to end with a temp settings file).
- `swift build --scratch-path .build/agents --target MeridianAgents` clean. A full-package build was interrupted once by another agent editing Sources/Meridian during the build; not related to this module.
- Real CLI check, temp settings file only (`claude -p "say hi" --settings <temp>`, real ~/.claude untouched): hooks fired and the log received
  `UserPromptSubmit`, `StopFailure`, `SessionEnd` lines for one session id (tracker parsed them; SessionEnd removed the session).
  **Not fully verified:** a normal `Stop` line. `claude -p` failed with "OAuth session expired and could not be refreshed" in this environment (also with a clean env), so the turn never completed. The Stop to done path is covered by unit tests with synthetic events only. Re-run after `claude /login`.
- Temp files and the temporary e2e test were removed.

## Notes for the orchestrator

- Privacy change applied (identifier fields only); docs/AGENTS.md states exactly what is stored.
- Hooks load at session start; running sessions need a restart after install.
