#!/usr/bin/env bash
# Update the PERSONAL Multica daemon (CLI profile "personal") from this checkout.
#
#   scripts/personal/mc-daemon-update.sh              pull + merge main, build CLI, restart daemon
#   scripts/personal/mc-daemon-update.sh --no-pull    skip git; just rebuild + restart
#   scripts/personal/mc-daemon-update.sh --backend    also rebuild multica-backend:personal and restart the backend container
#   scripts/personal/mc-daemon-update.sh -y           don't ask before restarting the daemon
#   scripts/personal/mc-daemon-update.sh --build-only build the CLI and stop (no git, no restart)
#
# Only touches the "personal" profile; the default-profile (work) daemon is left alone.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
BRANCH="personal/remote-db-timeouts"
FORK="hson98/multica"
UPSTREAM_URL="https://github.com/multica-ai/multica.git"
PROFILE="personal"
# Runtimes to keep disabled (pointed at a missing path so the daemon skips them).
DISABLED_ENV=(MULTICA_COPILOT_PATH=/nonexistent/copilot)

PULL=1 BACKEND=0 YES=0 BUILD_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --no-pull) PULL=0 ;;
    --backend) BACKEND=1 ;;
    -y|--yes) YES=1 ;;
    --build-only) BUILD_ONLY=1; PULL=0 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }

cd "$REPO"
CLI="$REPO/server/bin/multica"

if [[ $PULL -eq 1 ]]; then
  step "Đồng bộ code"
  current=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$current" != "$BRANCH" ]]; then
    echo "Đang ở nhánh '$current', cần ở '$BRANCH'. Chạy: git switch $BRANCH" >&2
    exit 1
  fi
  if command -v gh >/dev/null; then
    gh repo sync "$FORK" --branch main 2>&1 || warn "Không sync được fork $FORK (thiếu quyền?). Bấm 'Sync fork' trên GitHub nếu cần."
  fi
  git fetch origin
  # Merge, not rebase: this branch is pulled on more than one machine.
  if git rev-parse --verify -q "origin/$BRANCH" >/dev/null; then
    git merge --autostash --no-edit "origin/$BRANCH"
  fi
  git branch -f main origin/main
  if ! git merge --autostash --no-edit main; then
    echo >&2
    echo "Merge main bị conflict. Sửa conflict rồi 'git commit' (hoặc 'git merge --abort'), sau đó chạy lại với --no-pull." >&2
    exit 1
  fi
  if [[ -n "$(git log --oneline "origin/$BRANCH..HEAD" 2>/dev/null || echo new)" ]]; then
    warn "Nhánh có commit chưa push. Chạy 'git push -u origin $BRANCH' để máy khác pull được."
  fi
fi

step "Build CLI"
TAG=$(git ls-remote --tags --refs "$UPSTREAM_URL" 'v*' 2>/dev/null | sed 's#.*refs/tags/##' | sort -V | tail -1 || true)
if [[ -z "$TAG" ]]; then
  # Offline fallback: reuse the tag from the currently built binary.
  TAG=$("$CLI" version 2>/dev/null | sed -nE 's/^multica (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -1 || true)
  [[ -n "$TAG" ]] || { echo "Không xác định được version tag (mất mạng?)." >&2; exit 1; }
  warn "Không lấy được tag mới nhất, dùng lại $TAG"
fi
C=$(git rev-parse --short HEAD)
# The server only accepts semver / git-describe shapes; a bare commit hash
# makes it treat the daemon as "no CLI version" and blocks Create with agent.
VERSION="${TAG}-0-g${C}-personal"
(cd server && go build -ldflags "-X main.version=${VERSION} -X main.commit=${C} -X main.buildCommit=${C} -X main.date=$(date -u +%Y-%m-%dT%H:%M:%SZ)" -o bin/multica ./cmd/multica)
"$CLI" version | head -1
[[ $BUILD_ONLY -eq 1 ]] && exit 0

if [[ $BACKEND -eq 1 ]]; then
  step "Build + restart backend (multica-backend:personal)"
  if [[ ! -f docker-compose.personal.yml ]]; then
    echo "Thiếu docker-compose.personal.yml (file này không nằm trong git; tạo theo PERSONAL_SETUP.md)." >&2
    exit 1
  fi
  docker build -f Dockerfile -t multica-backend:personal .
  docker compose -f docker-compose.selfhost.yml -f docker-compose.personal.yml up -d backend
fi

step "Restart daemon [$PROFILE]"
if [[ ! -d "$HOME/.multica/profiles/$PROFILE" ]]; then
  echo "Chưa có profile '$PROFILE' trên máy này. Chạy trước:" >&2
  echo "  $CLI --profile $PROFILE setup self-host --server-url <backend-url> --app-url <app-url>" >&2
  exit 1
fi
if [[ $YES -eq 0 ]]; then
  read -r -p "Task đang chạy trên daemon sẽ bị ngắt. Restart ngay? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Bỏ qua restart. CLI mới đã build; chạy lại với --no-pull -y khi sẵn sàng."; exit 0; }
fi
"$CLI" --profile "$PROFILE" daemon stop || true
env "${DISABLED_ENV[@]}" "$CLI" --profile "$PROFILE" daemon start

step "Trạng thái"
"$CLI" --profile "$PROFILE" daemon status
