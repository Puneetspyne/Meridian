import Foundation

/// The POSIX sh script Claude Code runs for every hook event.
///
/// Constraints that shape it: it must never block Claude (always exit 0), must print nothing to stdout
/// (a UserPromptSubmit hook's stdout is injected into Claude's context), and may only use `/bin/sh`
/// builtins plus `date` (no jq, no python). The line it appends is
/// `{"ts": <epoch>, "event": "<name>", "payload": <stdin json>}`.
public enum HookScript {
    public static let fileName = "claude-hook.sh"
    public static let eventsFileName = "claude-events.jsonl"

    /// Payloads above this many characters (a Write of a big file, say) are replaced by a small stub that keeps
    /// the identifying fields, so the log stays small and holds as little of the user's code as possible.
    public static let oversizeLimit = 20_000

    public static let contents = #"""
    #!/bin/sh
    # Meridian: Claude Code hook. Appends one JSON line per event to claude-events.jsonl.
    # Prints nothing, always exits 0, so it can never block or alter a Claude session.
    # Remove with: Meridian > Settings > Agents > Remove hooks (or delete the entries pointing here from ~/.claude/settings.json).

    exec 2>/dev/null
    dir=${0%/*}
    out=${MERIDIAN_EVENTS_FILE:-"$dir/../claude-events.jsonl"}

    # Read stdin, joining lines (JSON whitespace between tokens is insignificant; newlines inside strings are escaped).
    p=
    while IFS= read -r l || [ -n "$l" ]; do p="$p$l"; done
    [ -n "$p" ] || p='{}'

    # Pull a simple string field out of compact JSON using parameter expansion only.
    field() {
      v=${p#*\""$1"\":\"}
      [ "$v" = "$p" ] && return 0
      printf '%s' "${v%%\"*}"
    }

    ev=${1:-$(field hook_event_name)}
    [ -n "$ev" ] || ev=unknown

    if [ "${#p}" -gt 20000 ]; then
      p="{\"oversize\":true,\"session_id\":\"$(field session_id)\",\"cwd\":\"$(field cwd)\",\"hook_event_name\":\"$ev\",\"tool_name\":\"$(field tool_name)\"}"
    fi

    ts=$(date +%s)
    printf '{"ts": %s, "event": "%s", "payload": %s}\n' "$ts" "$ev" "$p" >> "$out"
    exit 0
    """# + "\n"

    /// Writes the script (creating its directory) and marks it executable. Returns the script URL.
    @discardableResult
    public static func write(toDirectory hooksDirectory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: hooksDirectory, withIntermediateDirectories: true)
        let url = hooksDirectory.appendingPathComponent(fileName)
        let text = contents
        try Data(text.utf8).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
