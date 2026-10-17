#!/usr/bin/env bash
#
# Wiki.js 3.x - dev servers one-shot stop (backend + frontend)
#
# Usage: ./stop.sh
#
# 1) start.sh 가 남긴 pid 파일로 프로세스 트리 전체를 종료
# 2) 그래도 포트가 살아 있으면 (수동 실행 등) 포트 기준으로 종료
#    - 리스너의 부모가 node(npm/nodemon)면 부모부터 트리째 종료해서 재시작을 막음

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$ROOT/data/run"

log()  { printf '\033[1;36m[stop]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[stop]\033[0m %s\n' "$*"; }

topval() { sed -n "s/^$1:[[:space:]]*//p" "$ROOT/config.yml" | head -1 | tr -d "\"' " | tr -d $'\r'; }
devval() { sed -n '/^dev:/,$p' "$ROOT/config.yml" | sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" | head -1 | tr -d "\"' " | tr -d $'\r'; }

[ -f "$ROOT/config.yml" ] || { printf '[stop] config.yml 이 없습니다\n' >&2; exit 1; }

APP_PORT="$(topval port)"; APP_PORT="${APP_PORT:-3000}"
UI_PORT="$(devval port)";  UI_PORT="${UI_PORT:-3001}"

port_pids() { # $1=port -> LISTEN 중인 Windows PID 목록
  powershell -NoProfile -Command \
    "(Get-NetTCPConnection -LocalPort $1 -State Listen -ErrorAction SilentlyContinue).OwningProcess | Sort-Object -Unique" 2>/dev/null
}

parent_of() { powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"ProcessId=$1\").ParentProcessId" 2>/dev/null | tr -d $'\r[:space:]'; }
pname_of()  { powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"ProcessId=$1\").Name" 2>/dev/null | tr -d $'\r[:space:]'; }

kill_tree() { taskkill //F //T //PID "$1" >/dev/null 2>&1; }

stop_pidfile() { # $1=label $2=pidfile
  [ -f "$2" ] || return 0
  local msys wpid
  msys="$(tr -d $'\r[:space:]' <"$2")"
  wpid="$(ps -W 2>/dev/null | awk -v p="$msys" '$1==p {print $4; exit}')"
  rm -f "$2"
  if [ -n "$wpid" ]; then
    if kill_tree "$wpid"; then
      log "$1 - 프로세스 트리 종료 (pid $wpid)"
    else
      warn "$1 - 종료 실패 (pid $wpid)"
    fi
  else
    log "$1 - 저장된 프로세스가 이미 없음"
  fi
}

stop_port() { # $1=label $2=port
  local pids p par
  pids="$(port_pids "$2")"
  if [ -z "$pids" ]; then
    log "$1 (:$2) - 실행 중 아님"
    return 0
  fi
  for p in $pids; do
    kill_tree "$p"
    par="$(parent_of "$p")"
    if [ -n "$par" ] && [[ "$(pname_of "$par")" == node* ]]; then
      kill_tree "$par"   # nodemon/npm 이 살아 다시 띄우지 않도록 부모 트리도 종료
    fi
  done
  sleep 1
  if [ -n "$(port_pids "$2")" ]; then
    warn "$1 (:$2) - 일부 프로세스가 살아 있습니다"
  else
    log "$1 (:$2) - 중지됨"
  fi
}

stop_pidfile "백엔드" "$RUN/backend.pid"
stop_pidfile "프론트엔드" "$RUN/frontend.pid"
sleep 2   # 자식 프로세스 정리 대기

stop_port "백엔드" "$APP_PORT"
stop_port "프론트엔드" "$UI_PORT"

log "완료 - 다시 시작: ./start.sh"
