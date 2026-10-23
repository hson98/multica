#!/usr/bin/env bash
# docker compose for the personal stack (project multica-personal).
# Usage: mc-personal <compose args...>   e.g. mc-personal ps, mc-personal logs -f backend
set -euo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
[[ -f "$REPO/docker-compose.personal.yml" ]] || { echo "Thiếu $REPO/docker-compose.personal.yml (không nằm trong git; tạo theo PERSONAL_SETUP.md)." >&2; exit 1; }
exec docker compose --project-directory "$REPO" -f "$REPO/docker-compose.selfhost.yml" -f "$REPO/docker-compose.personal.yml" "$@"
