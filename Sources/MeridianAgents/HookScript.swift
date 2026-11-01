import Foundation

/// The POSIX sh script Claude Code runs for every hook event.
///
/// Constraints that shape it: it must never block Claude (always exit 0), must print nothing to stdout
/// (a UserPromptSubmit hook's stdout is injected into Claude's context), and may only use `/bin/sh`
/// builtins plus `date` (no jq, no python). The line it appends is
/// `{"ts": <epoch>, "event": "<name>", "payload": {identifier fields only}}`: session_id, hook_event_name, cwd,
/// tool_name, notification_type, stop_hook_active and, for Notification, the message cut to 200 characters.
/// Prompt text, tool inputs, tool responses and transcript contents are never stored.
public enum HookScript {
    public static let fileName = "claude-hook.sh"
    public static let eventsFileName = "claude-events.jsonl"

    /// Longest Notification message the script keeps, in characters.
    public static let messageLimit = 200

    public static let contents = #"""
    #!/bin/sh
    # Meridian: Claude Code hook. Appends one JSON line per event to claude-events.jsonl.
    # Stores identifier fields only: session_id, hook_event_name, cwd, tool_name, notification_type,
    # stop_hook_active and (Notification only) the message cut to 200 characters.
    # Prompt text, tool inputs, tool responses and transcript contents are never written.
    # Prints nothing, always exits 0, so it can never block or alter a Claude session.
    # Remove with: Meridian > Settings > Agents > Remove hooks (or delete the entries pointing here from ~/.claude/settings.json).

    exec 2>/dev/null
    dir=${0%/*}
    out=${MERIDIAN_EVENTS_FILE:-"$dir/../claude-events.jsonl"}

    # Read stdin, joining lines (JSON whitespace between tokens is insignificant; newlines inside strings are escaped).
    p=
    while IFS= read -r l || [ -n "$l" ]; do p="$p$l"; done

    # str KEY: the still-escaped value of the first compact `"KEY":"..."`, honouring \" inside the value.
    str() {
      rest=${p#*\""$1"\":\"}
      [ "$rest" = "$p" ] && return 0
      acc=
      while :; do
        chunk=${rest%%\"*}
        [ "$chunk" = "$rest" ] && return 0
        acc=$acc$chunk
        t=$chunk; n=0
        while [ "${t%\\}" != "$t" ]; do t=${t%\\}; n=$((n + 1)); done
        rest=${rest#"$chunk"\"}
        if [ $((n % 2)) -eq 1 ]; then acc=$acc\"; else break; fi
      done
      printf '%s' "$acc"
    }

    # bool KEY: true or false for `"KEY":true|false`.
    bool() {
      rest=${p#*\""$1"\":}
      [ "$rest" = "$p" ] && return 0
      case $rest in true*) printf true ;; false*) printf false ;; esac
    }

    # Cut at 200 characters without leaving a dangling escape that would make the line invalid JSON.
    clip() {
      t=$(printf '%.200s' "$1")
      while :; do
        case $t in
          *\\u???|*\\u??|*\\u?|*\\u) t=${t%\\u*}; continue ;;
        esac
        s=$t; n=0
        while [ "${s%\\}" != "$s" ]; do s=${s%\\}; n=$((n + 1)); done
        if [ $((n % 2)) -eq 1 ]; then t=${t%\\}; fi
        break
      done
      printf '%s' "$t"
    }

    ev=${1:-$(str hook_event_name)}
    [ -n "$ev" ] || ev=unknown
    body="\"hook_event_name\":\"$ev\""
    for k in session_id cwd tool_name notification_type; do
      v=$(str "$k")
      [ -n "$v" ] && body="$body,\"$k\":\"$v\""
    done
    v=$(bool stop_hook_active)
    [ -n "$v" ] && body="$body,\"stop_hook_active\":$v"
    if [ "$ev" = Notification ]; then
      v=$(str message)
      [ -n "$v" ] && body="$body,\"message\":\"$(clip "$v")\""
    fi

    ts=$(date +%s)
    printf '{"ts": %s, "event": "%s", "payload": {%s}}\n' "$ts" "$ev" "$body" >> "$out"
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
