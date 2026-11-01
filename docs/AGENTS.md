# Coding agents (Claude Code, Codex)

Meridian shows a Claude Code session that needs you (a permission prompt, a question, an idle prompt) as a
signal in the notch or corner, plus working and done states. Opt-in, off by default.

## What it does

1. On opt-in (Settings > Agents > Install hooks) Meridian writes a small `/bin/sh` script and adds hook entries
   to `~/.claude/settings.json`.
2. Claude Code runs the script for each event. The script appends one JSON line to a local log.
3. Meridian tails the log once a second and turns it into session states. Nothing leaves your Mac.

## Exactly what is written, and where

| Path | What |
| --- | --- |
| `~/Library/Application Support/Meridian/hooks/claude-hook.sh` | The hook script (mode 755). Uses only sh builtins and `date`. Prints nothing, always exits 0. |
| `~/Library/Application Support/Meridian/claude-events.jsonl` | One line per event: `{"ts", "event", "payload"}` with identifier fields only (see Privacy). Rotated to `claude-events.jsonl.1` above 5 MB. |
| `~/.claude/settings.json` | One hook group per event below, each `{"hooks":[{"type":"command","command":"<script path>","timeout":5}]}`. Everything else is preserved. Keys are sorted and the file is pretty-printed, so the first install may reorder keys. |
| `~/.claude/settings.json.meridian-backup` | Copy of the file as it was before the latest change. |
| `~/Library/Application Support/Meridian/agent-names.json` | Optional, you create it: `{"<session id or cwd or folder name>": "Title"}`. |

Events: UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, Elicitation,
ElicitationResult, Notification, Stop, StopFailure, SubagentStop, SessionEnd. No matchers are set.
Hooks load when a Claude Code session starts, so already-running sessions need a restart.

If settings.json is not valid JSON, Meridian refuses to touch it.

## States

working (UserPromptSubmit, tool events) -> needs you (a permission/idle/elicitation Notification or a
PermissionRequest/Elicitation event) -> cleared by the next PostToolUse, UserPromptSubmit or Stop -> done
(Stop). A working session silent for 90 s shows as idle (dimmed, not a signal). Done sessions leave after
10 minutes or when dismissed. Sessions with no event for 6 hours are dropped.

Resume link: `claude://resume?session=<id>`. If the Claude desktop app is not installed the UI shows the folder.

## Codex CLI (best effort, read-only)

If `~/.codex/sessions` exists, a rollout file modified in the last 30 s (today or yesterday's folder) is shown as
"working". Nothing is written for Codex, and there is no needs-you or done state.

## Privacy

- The log lives only on your disk. Meridian makes no network calls for this.
- The hook script stores identifier fields only. Per event line: `ts` (epoch seconds), `event`, and a payload holding
  `hook_event_name`, `session_id`, `cwd`, `tool_name`, `notification_type`, `stop_hook_active` (each only when the
  event has it) and, for Notification events only, `message` cut to 200 characters (it is the "needs your
  permission to use Bash" text that becomes the card detail).
- Never stored: prompt text, tool inputs, tool responses, the assistant's replies, the transcript path or any
  transcript contents, permission mode, tool use ids. The script extracts the fields above from Claude's compact
  JSON with shell parameter expansion and writes nothing else.
- `cwd` is your project folder path, which Meridian shows as the session name.
- Delete the log any time; it is recreated empty.

## Remove it

Settings > Agents > Remove hooks, or edit `~/.claude/settings.json` and delete the entries whose command is the
script path (or restore `settings.json.meridian-backup`). Removal deletes only Meridian's entries. The script and
log stay on disk; delete `~/Library/Application Support/Meridian/hooks` and `claude-events.jsonl*` to finish.
Keep the script until live Claude sessions end, otherwise they log a harmless "command not found".
