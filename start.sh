#!/usr/bin/env bash
#
# Wiki.js 3.x - dev servers one-shot start: backend + frontend
#
# Usage: ./start.sh
# Stop : ./stop.sh
#
# - Node.js 26+ / PostgreSQL 17+ (PostgreSQL must already be running)
# - runs npm install automatically when node_modules is missing
# - logs & pid files: data/run/  (data/ is gitignored)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$ROOT/data/run"
mkdir -p "$RUN"

log()  { printf '\033[1;36m[start]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[start]\033[0m %s\n' "$*" >&2; exit 1; }

port_open() { (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null; }
port_busy() { port_open 127.0.0.1 "$1"; }

wait_ready() { # $1=port $2=timeout_sec $3=pidfile $4=logfile (rc: 0=준비 1=시간초과 2=크래시)
  local i=0 mpid wpid
  mpid="$(cat "$3" 2>/dev/null || true)"
  until port_busy "$1"; do
    if [ -n "$mpid" ]; then
      wpid="$(ps -W 2>/dev/null | awk -v p="$mpid" '$1==p {print $4; exit}')"
      if [ -z "$wpid" ]; then return 2; fi
    fi
    # nodemon 은 앱이 크래시해도 살아서 재시작을 기다리므로 로그로 감지
    if grep -q "app crashed" "$4" 2>/dev/null; then return 2; fi
    i=$((i + 1))
    if [ "$i" -ge "$2" ]; then return 1; fi
    printf '.'
    sleep 1
  done
  echo
}

report_failure() { # $1=rc $2=logfile $3=timeout_message
  echo
  tail -n 20 "$2" || true
  if [ "$1" = 2 ]; then
    fail "프로세스가 부팅 중 크래시됐습니다 - 위 로그를 확인해 주세요"
  fi
  fail "$3"
}

# --- config.yml readers (top-level key / db: block / dev: block) ----------
topval() { sed -n "s/^$1:[[:space:]]*//p" "$ROOT/config.yml" | head -1 | tr -d "\"' " | tr -d $'\r'; }
dbval()  { sed -n '/^db:/,/^[^[:space:]#]/p' "$ROOT/config.yml" | sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" | head -1 | tr -d "\"' " | tr -d $'\r'; }
devval() { sed -n '/^dev:/,$p' "$ROOT/config.yml" | sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" | head -1 | tr -d "\"' " | tr -d $'\r'; }

[ -f "$ROOT/config.yml" ] || fail "config.yml 이 없습니다 - config.sample.yml 을 복사해 주세요"

APP_PORT="$(topval port)"; APP_PORT="${APP_PORT:-3000}"
UI_PORT="$(devval port)";  UI_PORT="${UI_PORT:-3001}"
DB_HOST="$(dbval host)";   DB_HOST="${DB_HOST:-localhost}"
DB_PORT="$(dbval port)";   DB_PORT="${DB_PORT:-5432}"

# --- prerequisites ---------------------------------------------------------

command -v node >/dev/null 2>&1 || fail "node 를 찾을 수 없습니다 - Node.js 26+ 필요"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt 26 ]; then
  fail "Node.js 26+ 가 필요합니다 (backend/index.ts 하드 체크, 현재 $(node -v)). Node.js 26 이상을 설치 후 다시 실행해 주세요 (nvm-windows: nvm install 26 && nvm use 26)"
fi

if ! port_open "$DB_HOST" "$DB_PORT"; then
  fail "PostgreSQL($DB_HOST:$DB_PORT) 에 접속할 수 없습니다 - PostgreSQL 을 먼저 시작해 주세요"
fi

[ -d "$ROOT/backend/node_modules" ] || { log "backend 의존성 설치 중 (npm install)..."; (cd "$ROOT/backend" && npm install) || fail "backend npm install 실패"; }
[ -d "$ROOT/frontend/node_modules" ] || { log "frontend 의존성 설치 중 (npm install)..."; (cd "$ROOT/frontend" && npm install) || fail "frontend npm install 실패"; }

launch() { # $1=dir $2=logfile $3=pidfile
  nohup bash -c "cd '$1' && npm run dev" >"$2" 2>&1 &
  echo $! >"$3"
}

# --- backend ---------------------------------------------------------------

if port_busy "$APP_PORT"; then
  log "백엔드가 이미 :$APP_PORT 에서 실행 중 - 건너뜀"
else
  log "백엔드 시작 중 (:$APP_PORT) - 부팅에 ~30초 정도 걸립니다"
  launch "$ROOT/backend" "$RUN/backend.log" "$RUN/backend.pid"
  rc=0
  wait_ready "$APP_PORT" 120 "$RUN/backend.pid" "$RUN/backend.log" || rc=$?
  if [ "$rc" -ne 0 ]; then
    report_failure "$rc" "$RUN/backend.log" "백엔드가 120초 안에 :$APP_PORT 를 열지 못했습니다 (로그: data/run/backend.log)"
  fi
  log "백엔드 준비됨"
fi

# --- frontend --------------------------------------------------------------

if port_busy "$UI_PORT"; then
  log "프론트엔드가 이미 :$UI_PORT 에서 실행 중 - 건너뜀"
else
  log "프론트엔드 시작 중 (:$UI_PORT)"
  launch "$ROOT/frontend" "$RUN/frontend.log" "$RUN/frontend.pid"
  rc=0
  wait_ready "$UI_PORT" 90 "$RUN/frontend.pid" "$RUN/frontend.log" || rc=$?
  if [ "$rc" -ne 0 ]; then
    report_failure "$rc" "$RUN/frontend.log" "프론트엔드가 90초 안에 :$UI_PORT 를 열지 못했습니다 (로그: data/run/frontend.log)"
  fi
  log "프론트엔드 준비됨"
fi

# --- done ------------------------------------------------------------------

log "모두 실행 중 -"
echo "  위키 UI     http://localhost:$UI_PORT"
echo "  API         http://localhost:$APP_PORT   (Swagger UI: /_api)"
echo "  기본 계정   admin@example.com / 12345678"
echo "  로그        data/run/backend.log / data/run/frontend.log"
echo "  중지        ./stop.sh"
