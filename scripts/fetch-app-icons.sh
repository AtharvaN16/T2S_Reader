#!/bin/bash
# scripts/fetch-app-icons.sh — pulls the ten app icons out of the Figma file ("T2S Reader", section
# "App icons", node 97:36) through the Figma desktop app's local Dev Mode MCP server. Figma must be
# open on this Mac and signed in to an account that can see the file; the server listens on
# 127.0.0.1:3845 and needs no token.
#
# Each icon comes back as a 1024 × 1024 PNG screenshot of its rounded-rectangle node, so it has
# transparent corners; `scripts/flatten-app-icon.swift` fills them and strips the alpha before the
# pixels go into the catalog (App Store Connect rejects an icon with an alpha channel, ITMS-90717).
#
#   scripts/fetch-app-icons.sh [output-dir]      # default /tmp/figma-icons
set -euo pipefail
OUT=${1:-/tmp/figma-icons}
mkdir -p "$OUT"
MCP=http://127.0.0.1:3845/mcp
FILE=r0GICiHtjZZatMxMHWhRJg

post() {
    curl -s -m 600 -X POST "$MCP" -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' ${SID:+-H "mcp-session-id: $SID"} -d "$1"
}

SID=
SID=$(curl -s -m 10 -X POST "$MCP" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"fetch-app-icons","version":"1.0"}}}' \
    -D - -o /dev/null | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}' | tr -d '\r')
[ -n "$SID" ] || { echo "no session from $MCP — is the Figma desktop app open?" >&2; exit 1; }
post '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null

# The catalog's names (`AppIcon.title`) and the nodes that carry them, in the grid's order.
while read -r name node; do
    printf '%-10s %-6s ' "$name" "$node"
    post "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"get_screenshot\",\"arguments\":{\"fileKey\":\"$FILE\",\"nodeId\":\"$node\"}}}" \
        | sed -n 's/^data: //p' \
        | python3 -c '
import sys, json, base64
out = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    r = json.loads(line).get("result", {})
    for c in r.get("content", []):
        if c.get("type") == "image":
            open(out, "wb").write(base64.b64decode(c["data"])); print("ok", end=" ")
' "$OUT/$name.png"
    sips -g pixelWidth -g pixelHeight "$OUT/$name.png" | tail -2 | awk '{printf "%s ", $2}'; echo
done <<'LIST'
Default 96:18
Dark 96:19
Stealth 97:38
Rainbow 96:22
Halloween 96:23
Amber 96:25
Candy 96:24
Zen 97:26
Metal 89:3
Pixel 96:21
LIST
echo "done: $OUT"
