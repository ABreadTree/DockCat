import Foundation

enum AgentBridgeHelper {
    static let executableName = "dockcat-agent-event"
    static let managedMarker = "--dockcat-managed"

    static func script(defaultPort: Int = 8765) -> String {
        """
        #!/bin/sh
        set -u

        AGENT="agent"
        SESSION="default"
        STATUS="info"
        MESSAGE=""
        HINT=""
        PORT="\(AppSettings.normalizedAgentHTTPPort(defaultPort))"

        while [ "$#" -gt 0 ]; do
          case "$1" in
            --agent)
              AGENT="${2:-agent}"
              shift 2
              ;;
            --session)
              SESSION="${2:-default}"
              shift 2
              ;;
            --status)
              STATUS="${2:-info}"
              shift 2
              ;;
            --message)
              MESSAGE="${2:-}"
              shift 2
              ;;
            --hint)
              HINT="${2:-}"
              shift 2
              ;;
            --port)
              PORT="${2:-\(AppSettings.normalizedAgentHTTPPort(defaultPort))}"
              shift 2
              ;;
            \(managedMarker))
              shift
              ;;
            --chain)
              shift
              if [ "${1:-}" = "--" ]; then
                shift
              fi
              break
              ;;
            *)
              shift
              ;;
          esac
        done

        if [ "$#" -gt 0 ]; then
          "$@" >/dev/null 2>&1 || true
        fi

        STDIN_PAYLOAD=""
        if [ ! -t 0 ]; then
          STDIN_PAYLOAD="$(cat)"
        fi

        if [ -z "$MESSAGE" ] && [ -n "$STDIN_PAYLOAD" ]; then
          MESSAGE="$(printf '%s' "$STDIN_PAYLOAD" | tr '\\n' ' ' | cut -c 1-180)"
        fi

        json_escape() {
          printf '%s' "$1" | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g'
        }

        BODY="$(printf '{"agent":"%s","session":"%s","status":"%s","message":"%s","hint":"%s"}' "$(json_escape "$AGENT")" "$(json_escape "$SESSION")" "$(json_escape "$STATUS")" "$(json_escape "$MESSAGE")" "$(json_escape "$HINT")")"

        /usr/bin/curl --silent --show-error --max-time 0.7 -X POST "http://127.0.0.1:${PORT}/agent-events" -H 'Content-Type: application/json' --data "$BODY" >/dev/null 2>&1 || true
        exit 0
        """
    }

    static func commandArguments(
        helperPath: String,
        agent: AgentBridgeAgentID,
        port: Int,
        status: AgentStatus = .info,
        session: String = "default",
        message: String? = nil,
        hint: String? = nil,
        chainedCommand: [String] = []
    ) -> [String] {
        var arguments = [
            helperPath,
            managedMarker,
            "--agent", agent.rawValue,
            "--session", session,
            "--status", status.rawValue,
            "--port", String(AppSettings.normalizedAgentHTTPPort(port))
        ]
        if let message, !message.isEmpty {
            arguments.append(contentsOf: ["--message", message])
        }
        if let hint, !hint.isEmpty {
            arguments.append(contentsOf: ["--hint", hint])
        }
        if !chainedCommand.isEmpty {
            arguments.append(contentsOf: ["--chain", "--"])
            arguments.append(contentsOf: chainedCommand)
        }
        return arguments
    }
}
