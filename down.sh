#!/usr/bin/env bash
# down.sh — SAGE 전체 종료 스크립트 (모든 백엔드/프론트 중지 + 포트 강제정리 옵션)
# 사용법:
#   bash down.sh              # 정상 중지 루틴
#   FORCE=1 bash down.sh      # stop 실패 시 포트 강제 kill 포함
#
# 옵션(환경변수):
#   FORCE=0                   # 1이면 지정 포트의 LISTEN 프로세스 강제 종료
#   PORTS="8000 8003 8103 8104 5173 3000"  # 강제 종료 대상 포트 목록

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="${ROOT_DIR}/setup"
PORTS="${PORTS:-8000 8003 8103 8104 5173 3000}"
FORCE="${FORCE:-0}"

log()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

stop_if_exists() {
  local name="$1"
  local script="${SETUP_DIR}/${name}"
  if [ -f "$script" ]; then
    log "중지 요청 → ${name}"
    bash "$script" stop >/dev/null 2>&1 || warn "${name} stop 반환값 비정상 (무시)"
  fi
}

status_if_exists() {
  local name="$1"
  local script="${SETUP_DIR}/${name}"
  if [ -f "$script" ]; then
    log "상태 확인 → ${name}"
    bash "$script" status || true
  fi
}

kill_ports() {
  local killed=0
  for p in $PORTS; do
    if command -v lsof >/dev/null 2>&1; then
      local pids
      pids="$(lsof -iTCP:"$p" -sTCP:LISTEN -t 2>/dev/null | tr '\n' ' ' || true)"
      if [ -n "${pids:-}" ]; then
        warn "포트 ${p} 사용 프로세스 강제 종료: ${pids}"
        kill $pids 2>/dev/null || true
        sleep 0.5
        killed=1
      fi
    fi
  done
  [ "$killed" = "1" ] && ok "포트 점유 프로세스 강제 종료 완료" || ok "강제 종료 대상 포트 점유 없음"
}

log "=== 모든 컴포넌트 중지 시작 ==="

# 종료 순서: 프론트 → 분석기 → 라인리지 → 감사 → 매핑-쇼 → 콜렉터
stop_if_exists "set-front.sh"
stop_if_exists "set-analyzer.sh"
stop_if_exists "set-lineage.sh"
stop_if_exists "set-com-audit.sh"
stop_if_exists "set-com-show.sh"
stop_if_exists "set-collector.sh"

# .pid 파일만 남은 케이스를 위해 한 번 더 stop 시도(있으면)
for s in set-front.sh set-analyzer.sh set-lineage.sh set-com-audit.sh set-com-show.sh set-collector.sh; do
  [ -f "${SETUP_DIR}/${s}" ] && bash "${SETUP_DIR}/${s}" stop >/dev/null 2>&1 || true
done

ok "정상 중지 루틴 완료"

if [ "$FORCE" = "1" ]; then
  log "FORCE=1 → 포트 강제 종료 수행"
  kill_ports
fi

log "=== 현재 상태 ==="
for s in set-collector.sh set-com-show.sh set-com-audit.sh set-lineage.sh set-analyzer.sh set-front.sh; do
  status_if_exists "$s"
done

ok "모든 서비스 내림 완료 ✅"
