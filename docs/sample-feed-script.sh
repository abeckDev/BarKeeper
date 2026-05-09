#!/usr/bin/env bash
# sample-feed-script.sh — Example script for BarKeeper's "feed" resource type.
#
# A feed script must:
#   • Exit with code 0 on success (non-zero is treated as an error).
#   • Print a single JSON object to stdout matching the FeedPayload schema.
#
# Any other output (stderr, earlier stdout lines from login-shell noise)
# is tolerated — BarKeeper extracts the last top-level JSON object.

set -euo pipefail

# ── Example: simulate fetching items from an external source ──────────

items='[]'
new_count=0

# In a real script you would query an API, parse a log, read a file, etc.
# Here we just build a static list for demonstration purposes.

items=$(cat <<'JSON'
[
  {
    "name": "Deploy #42 succeeded",
    "subtitle": "main → production",
    "detail": "Commit abc1234 by alice — deployed 5 min ago",
    "isNew": true
  },
  {
    "name": "Deploy #41 succeeded",
    "subtitle": "main → staging",
    "detail": "Commit def5678 by bob — deployed 2 hours ago",
    "isNew": false
  },
  {
    "name": "Deploy #40 failed",
    "subtitle": "main → production",
    "detail": "Commit 789abcd by carol — health-check timeout",
    "isNew": true
  }
]
JSON
)
new_count=2

# ── Emit the FeedPayload JSON ────────────────────────────────────────

cat <<EOF
{
  "schemaVersion": 1,
  "title": "Recent Deployments",
  "checkedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "items": ${items},
  "newCount": ${new_count}
}
EOF
