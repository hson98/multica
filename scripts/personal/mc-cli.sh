#!/usr/bin/env bash
# The multica CLI built from this checkout, bound to the "personal" profile.
# Usage: mc-cli <multica args...>   e.g. mc-cli daemon status
set -euo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
CLI="$REPO/server/bin/multica"
[[ -x "$CLI" ]] || { echo "Chưa build $CLI. Chạy: mc-daemon-update --no-pull" >&2; exit 1; }
exec "$CLI" --profile personal "$@"
