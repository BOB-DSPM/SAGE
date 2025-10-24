#!/usr/bin/env bash
# setup.sh — SAGE 전체 초기화/기동 마스터 스크립트
# 순서대로 각 setup/* 스크립트를 실행합니다.
#
# 사용법:
#   bash setup.sh up         # 필수 점검 → 백엔드들 → 프론트까지 순차 기동(기본)
#   bash setup.sh restart    # 모든 컴포넌트 재시작
#   bash setup.sh stop       # 모든 컴포넌트 중지
#   bash setup.sh status     # 상태 점검
#   bash setup.sh logs       # 각 컴포넌트 최근 로그 팔로우(순차)
#
# 옵션(환경변수):
#   RETRIES=2                # 실패 시 재시도 횟수
#   FAST=0                   # 1이면 Collector+Show 병렬 기동
#   SKIP_AWS_CHECK=0         # 1: check-aws.sh 건너뜀
#   SKIP_GIT_CHECK=0         # 1: check-git.sh 건너뜀
#   SKIP_COLLECTOR=0
#   SKIP_COM_SHOW=0
#   SKIP_COM_AUDIT=0
#   SKIP_LINEAGE=0
#   SKIP_ANALYZER=0
#   SKIP_FRONT=0

set -euo pipefail

### ===== 기본 경로/로그 =====
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="${ROOT_DIR}/setup"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"

RETRIES="${RETRIES:-2}"
FAST="${FAST:-0}"

SKIP_AWS_CHECK="${SKIP_AWS_CHECK:-0}"
SKIP_GIT_CHECK="${SKIP_GIT_CHECK:-0}"
SKIP_COLLECTOR="${SKIP_COLLECTOR:-0}"
SKIP_COM_SHOW="${SKIP_COM_SHOW:-0}"
SKIP_COM_AUDIT="${SKIP_COM_AUDIT:-0}"
SKIP_LINEAGE="${SKIP_LINEAGE:-0}"
SKIP_ANALYZER="${SKIP_ANALYZER:-0}"
SKIP_FRONT="${SKIP_FRONT:-0}"

### ===== 출력 헬퍼 =====
log()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

need_file() {
  local f="$1"
  [ -f "$f" ] || { err "파일 없음: $f"; exit 1; }
  [ -x "$f" ] || chmod +x "$f" || true
}

run_with_retry() {
  # $1: 로그이름, $2...: 실행 커맨드
  local name="$1"; shift
  local attempt=0
  local rc=0
  local logf="${LOG_DIR}/${name}-$(date +%Y%m%d-%H%M%S).log"

  while :; do
    attempt=$((attempt+1))
    log "실행(${name}) 시도 ${attempt}/${RETRIES} …"
    if "$@" >"$logf" 2>&1; then
      ok "${name} 완료 (로그: ${logf})"
      rc=0; break
    else
      rc=$?
      warn "${name} 실패(rc=${rc}) (로그: ${logf})"
      if [ "$attempt" -lt "$RETRIES" ]; then
        sleep 1
        continue
      fi
      break
    fi
  done
  return "$rc"
}

### ===== 개별 단계 래퍼 =====
check_git() {
  [ "$SKIP_GIT_CHECK" = "1" ] && { warn "check-git 건너뜀"; return 0; }
  need_file "${SETUP_DIR}/check-git.sh"
  run_with_retry "check-git" bash "${SETUP_DIR}/check-git.sh"
}
check_aws() {
  [ "$SKIP_AWS_CHECK" = "1" ] && { warn "check-aws 건너뜀"; return 0; }
  need_file "${SETUP_DIR}/check-aws.sh"
  run_with_retry "check-aws" bash "${SETUP_DIR}/check-aws.sh"
}

# ★ 시작 시에는 인자 없이 실행 (각 set-*.sh 가 “그냥 실행하면 기동”하도록 가정)
start_collector()  { [ "$SKIP_COLLECTOR" = "1" ] && { warn "collector 건너뜀"; return 0; }; need_file "${SETUP_DIR}/set-collector.sh";  run_with_retry "collector-run"  bash "${SETUP_DIR}/set-collector.sh"; }
start_com_show()   { [ "$SKIP_COM_SHOW" = "1" ] && { warn "com-show 건너뜀"; return 0; };  need_file "${SETUP_DIR}/set-com-show.sh";   run_with_retry "com-show-run"   bash "${SETUP_DIR}/set-com-show.sh"; }
start_com_audit()  { [ "$SKIP_COM_AUDIT" = "1" ] && { warn "com-audit 건너뜀"; return 0; }; need_file "${SETUP_DIR}/set-com-audit.sh";  run_with_retry "com-audit-run"  bash "${SETUP_DIR}/set-com-audit.sh"; }
start_lineage()    { [ "$SKIP_LINEAGE" = "1" ] && { warn "lineage 건너뜀"; return 0; };    need_file "${SETUP_DIR}/set-lineage.sh";    run_with_retry "lineage-run"    bash "${SETUP_DIR}/set-lineage.sh"; }
start_analyzer()   { [ "$SKIP_ANALYZER" = "1" ] && { warn "analyzer 건너뜀"; return 0; };  need_file "${SETUP_DIR}/set-analyzer.sh";   run_with_retry "analyzer-run"   bash "${SETUP_DIR}/set-analyzer.sh"; }
start_front()      { [ "$SKIP_FRONT" = "1" ] && { warn "front 건너뜀"; return 0; };        need_file "${SETUP_DIR}/set-front.sh";      run_with_retry "front-run"      bash "${SETUP_DIR}/set-front.sh"; }

# 정지/상태/로그는 기존 인자 유지
stop_all() {
  for s in set-front.sh set-analyzer.sh set-lineage.sh set-com-audit.sh set-com-show.sh set-collector.sh; do
    if [ -f "${SETUP_DIR}/${s}" ]; then
      log "중지: ${s}"
      bash "${SETUP_DIR}/${s}" stop >/dev/null 2>&1 || true
    fi
  done
  ok "모든 서비스 중지 요청 완료"
}

status_all() {
  for s in set-collector.sh set-com-show.sh set-com-audit.sh set-lineage.sh set-analyzer.sh set-front.sh; do
    if [ -f "${SETUP_DIR}/${s}" ]; then
      log "상태: ${s}"
      bash "${SETUP_DIR}/${s}" status || true
    fi
  done
}

logs_all() {
  for s in set-collector.sh set-com-show.sh set-com-audit.sh set-lineage.sh set-analyzer.sh set-front.sh; do
    if [ -f "${SETUP_DIR}/${s}" ]; then
      log "로그 팔로우 시작(5초): ${s}"
      ( bash "${SETUP_DIR}/${s}" logs & sleep 5; pkill -P $$ tail 2>/dev/null || true ) || true
      echo "------------------------------------------------------------"
    fi
  done
  ok "로그 프리뷰 완료"
}

### ===== 시나리오: up =====
do_up() {
  log "=== 0) 사전 점검 ==="
  check_git
  check_aws

  log "=== 1) 베이스 서비스 기동 (Collector, Mapping-Show) ==="
  if [ "$FAST" = "1" ]; then
    start_collector & p1=$!
    start_com_show  & p2=$!
    wait $p1 || { err "collector 기동 실패"; exit 1; }
    wait $p2 || { err "com-show 기동 실패"; exit 1; }
  else
    start_collector
    start_com_show
  fi

  log "=== 2) 감사 서비스 (Compliance-Audit) ==="
  start_com_audit

  log "=== 3) 기타 백엔드 (Lineage, Analyzer) ==="
  if [ "$FAST" = "1" ]; then
    start_lineage & p3=$!
    start_analyzer & p4=$!
    wait $p3 || { err "lineage 기동 실패"; exit 1; }
    wait $p4 || { err "analyzer 기동 실패"; exit 1; }
  else
    start_lineage
    start_analyzer
  fi

  log "=== 4) 프론트엔드 ==="
  start_front

  ok "모든 컴포넌트 기동 완료 🎉"
  status_all
  log "문서 예: http://localhost:8003/docs (Compliance-show), http://localhost:8104/docs (Compliance-audit)"
}

### ===== 메인 엔트리 =====
cmd="${1:-up}"
case "$cmd" in
  up)
    do_up
    ;;
  restart)
    stop_all
    do_up
    ;;
  stop)
    stop_all
    ;;
  status)
    status_all
    ;;
  logs)
    logs_all
    ;;
  *)
    echo "Usage: $0 {up|restart|stop|status|logs}"
    exit 1
    ;;
esac
