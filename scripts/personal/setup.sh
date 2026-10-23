#!/usr/bin/env bash
# Quick setup for the PERSONAL Multica stack on a new machine.
#
#   git clone git@github-personal:hson98/multica.git && cd multica
#   git switch personal/remote-db-timeouts
#   cp <đường dẫn tới .env đã lưu> .env
#   ./scripts/personal/setup.sh
#
# Safe to re-run: every step is idempotent. Needs git, go, docker (running) and curl.
# What it does:
#   1. checks prerequisites and .env
#   2. links mc-cli / mc-personal / mc-daemon-update into ~/.local/bin
#   3. builds multica-backend:personal and starts the stack (backend, frontend, redis)
#   4. waits for the backend (first run on an empty DB applies migrations: ~5 min)
#   5. builds the CLI and logs the "personal" profile in (browser login)
#   6. (re)starts the daemon with the personal runtime settings
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
BRANCH="personal/remote-db-timeouts"
BIN_DIR="$HOME/.local/bin"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx %s\033[0m\n' "$*" >&2; exit 1; }

cd "$REPO"

step "Kiểm tra môi trường"
for c in git go docker curl; do
  command -v "$c" >/dev/null || die "Thiếu '$c'. Cài trước rồi chạy lại."
done
docker info >/dev/null 2>&1 || die "Docker chưa chạy (mở Docker Desktop / colima start)."
[[ "$(git rev-parse --abbrev-ref HEAD)" == "$BRANCH" ]] || warn "Đang không ở nhánh $BRANCH (git switch $BRANCH)."

[[ -f .env ]] || die "Chưa có .env ở $REPO. Copy file .env đã lưu vào đây."
envval() { sed -nE "s/^$1=(.*)$/\1/p" .env | tail -1 | sed -E 's/^"(.*)"$/\1/'; }
for k in DATABASE_URL JWT_SECRET MULTICA_VCS_SECRET_KEY; do
  [[ -n "$(envval "$k")" ]] || die ".env thiếu giá trị $k."
done
[[ "$(envval COMPOSE_PROJECT_NAME)" == "multica-personal" ]] || die ".env phải có COMPOSE_PROJECT_NAME=multica-personal."
PORT="$(envval PORT)"; PORT="${PORT:-8180}"
FRONTEND_PORT="$(envval FRONTEND_PORT)"; FRONTEND_PORT="${FRONTEND_PORT:-3100}"
[[ -n "$(envval MULTICA_TELEGRAM_SECRET_KEY)" ]] || warn "MULTICA_TELEGRAM_SECRET_KEY trống: Telegram sẽ tắt."
echo "OK: backend :$PORT, frontend :$FRONTEND_PORT"

step "Cài lệnh mc-cli, mc-personal, mc-daemon-update vào $BIN_DIR"
mkdir -p "$BIN_DIR"
for n in mc-cli mc-personal mc-daemon-update; do
  chmod +x "$REPO/scripts/personal/$n.sh"
  ln -sf "$REPO/scripts/personal/$n.sh" "$BIN_DIR/$n"
done
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR chưa có trong PATH. Thêm vào ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
MC_PERSONAL="$REPO/scripts/personal/mc-personal.sh"
MC_CLI="$REPO/scripts/personal/mc-cli.sh"

step "Build backend image (multica-backend:personal)"
docker build -f Dockerfile -t multica-backend:personal .

step "Khởi động stack"
"$MC_PERSONAL" pull frontend redis
"$MC_PERSONAL" up -d

step "Chờ backend sẵn sàng (lần đầu trên DB trống có thể mất ~5 phút)"
deadline=$((SECONDS + 900))
until curl -fsS "http://localhost:$PORT/health" >/dev/null 2>&1; do
  if (( SECONDS > deadline )); then
    "$MC_PERSONAL" logs --tail 40 backend || true
    die "Backend chưa lên sau 15 phút. Xem log ở trên (sai DATABASE_URL? DB chặn IP máy này?)."
  fi
  printf '.'; sleep 5
done
echo " backend OK"

step "Build CLI"
"$REPO/scripts/personal/mc-daemon-update.sh" --build-only

if [[ ! -s "$HOME/.multica/profiles/personal/config.json" ]]; then
  step "Đăng nhập profile 'personal'"
  echo "Trình duyệt sẽ mở trang đăng nhập. Nhập email, rồi lấy mã xác thực bằng lệnh (ở terminal khác):"
  echo "  mc-personal logs backend | grep 'Verification code' | tail -1"
  "$MC_CLI" setup self-host --server-url "http://localhost:$PORT" --app-url "http://localhost:$FRONTEND_PORT"
else
  echo "Profile 'personal' đã đăng nhập, bỏ qua bước login."
fi

step "Khởi động daemon"
"$REPO/scripts/personal/mc-daemon-update.sh" --no-pull -y

cat <<EOF

Xong. Mở http://localhost:$FRONTEND_PORT
  mc-cli daemon status        trạng thái daemon / runtime
  mc-personal ps | logs -f backend
  mc-daemon-update            cập nhật code + build + restart daemon
EOF
