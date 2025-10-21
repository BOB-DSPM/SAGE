#!/usr/bin/env bash
# stack.sh - DSPM 스택 로컬 실행/중지 스크립트
# 브리지 네트워크에서 컨테이너 이름으로 상호 통신하며,
# 프론트(Nginx)가 내부 서비스로 리버스 프록시합니다.

set -euo pipefail

### ===============================
### 기본 포트 (호스트 노출 포트)
### ===============================
DASHBOARD_PORT="${DASHBOARD_PORT:-3000}"   # comnyang/sage-front (Nginx)
LINEAGE_PORT="${LINEAGE_PORT:-8300}"       # comnyang/sage-lineage
ANALYZER_PORT="${ANALYZER_PORT:-8400}"     # comnyang/sage-analyzer
COLLECTOR_PORT="${COLLECTOR_PORT:-8103}"   # comnyang/sage-collector
SHOW_PORT="${SHOW_PORT:-8003}"             # comnyang/sage-compliance-show
AUDIT_PORT="${AUDIT_PORT:-8104}"           # comnyang/sage-compliance-audit (collector와 충돌 피하려고 8104 권장)

### ===============================
### 내부 포트 (컨테이너 내부 고정 포트)
### ===============================
IN_DASHBOARD=3000
IN_LINEAGE=8300
IN_ANALYZER=8400
IN_COLLECTOR=8103
IN_SHOW=8003
IN_AUDIT=8103

### ===============================
### 옵션
### ===============================
STACK_NET="${STACK_NET:-sage-net}"

# EXPOSE_BACKENDS=0 이면 대시보드만 외부 노출(권장: 프론트 프록시 전용)
EXPOSE_BACKENDS="${EXPOSE_BACKENDS:-1}"

# AWS 자격증명 전달 방식
# - USE_AWS_VOLUME=1 → ~/.aws 를 /root/.aws:ro로 마운트(컨테이너 내 루트 필요 시)
# - USE_AWS_VOLUME=0 → 환경변수로 자격증명 전달
USE_AWS_VOLUME="${USE_AWS_VOLUME:-0}"

# 자격증명 환경변수(ENV 방식일 때만 사용)
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"             # 세션 사용하는 경우만
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"

### ===============================
### 이미지 이름
### ===============================
IMG_DASHBOARD="${IMG_DASHBOARD:-comnyang/sage-front:latest}"
IMG_LINEAGE="${IMG_LINEAGE:-comnyang/sage-lineage:latest}"
IMG_ANALYZER="${IMG_ANALYZER:-comnyang/sage-analyzer:latest}"
IMG_COLLECTOR="${IMG_COLLECTOR:-comnyang/sage-collector:latest}"
IMG_SHOW="${IMG_SHOW:-comnyang/sage-compliance-show:latest}"
IMG_AUDIT="${IMG_AUDIT:-comnyang/sage-compliance-audit:latest}"

### ===============================
### 공통 유틸 함수
### ===============================
log() { printf "%b\n" "$*"; }

ensure_network() {
  if ! docker network inspect "$STACK_NET" >/dev/null 2>&1; then
    log "[i] create network: $STACK_NET"
    docker network create "$STACK_NET"
  fi
}

aws_env_args() {
  if [[ "$USE_AWS_VOLUME" == "1" ]]; then
    # 루트 홈 기준 마운트가 필요한 이미지만 유효함(대부분 OK)
    echo "-v $HOME/.aws:/root/.aws:ro -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
  else
    # 환경변수로 전달
    echo "-e AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} -e AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} \
          ${AWS_SESSION_TOKEN:+-e AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}} \
          -e AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"
  fi
}

pull_images() {
  log "[i] pulling images..."
  docker pull "$IMG_DASHBOARD" || true
  docker pull "$IMG_LINEAGE"   || true
  docker pull "$IMG_ANALYZER"  || true
  docker pull "$IMG_COLLECTOR" || true
  docker pull "$IMG_SHOW"      || true
  docker pull "$IMG_AUDIT"     || true
}

rm_if_exists() {
  local name="$1"
  if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
    log "[i] remove existing: $name"
    docker rm -f "$name" >/dev/null 2>&1 || true
  fi
}

# 컨테이너별 포트 매핑 인자
port_args() {
  local name="$1"
  case "$name" in
    sage-dashboard)
      echo "-p ${DASHBOARD_PORT}:${IN_DASHBOARD}"
      ;;
    *)
      if [[ "$EXPOSE_BACKENDS" == "1" ]]; then
        case "$name" in
          sage-collector)        echo "-p ${COLLECTOR_PORT}:${IN_COLLECTOR}";;
          sage-compliance-show)  echo "-p ${SHOW_PORT}:${IN_SHOW}";;
          sage-compliance-audit) echo "-p ${AUDIT_PORT}:${IN_AUDIT}";;
          sage-analyzer)         echo "-p ${ANALYZER_PORT}:${IN_ANALYZER}";;
          sage-lineage)          echo "-p ${LINEAGE_PORT}:${IN_LINEAGE}";;
          *) echo "";;
        esac
      else
        echo ""  # 내부 전용
      fi
      ;;
  esac
}

wait_http_ok() {
  # wait_http_ok <host> <port> <path> <timeout_sec>
  local host="$1" port="$2" path="${3:-/health}" timeout="${4:-30}"
  local start ts
  start="$(date +%s)"
  while true; do
    if curl -fsS "http://${host}:${port}${path}" >/dev/null 2>&1; then
      log "[ok] http://${host}:${port}${path} is ready"
      return 0
    fi
    ts="$(date +%s)"
    if (( ts - start >= timeout )); then
      log "[warn] timeout waiting for http://${host}:${port}${path}"
      return 1
    fi
    sleep 1
  done
}

status_table() {
  printf "%-24s %-12s %-8s %-10s %s\n" "NAME" "STATE" "PORTS" "IMAGE" "IP"
  printf "%-24s %-12s %-8s %-10s %s\n" "----" "-----" "-----" "-----" "--"
  docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}' \
  | while IFS=$'\t' read -r n s p i; do
      # IP 출력(bridge일 때)
      ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$n" 2>/dev/null || echo "-")
      printf "%-24s %-12s %-8s %-10s %s\n" "$n" "$s" "${p:-'-'}" "$i" "${ip:-'-'}"
    done
}

### ===============================
### up/down/logs/status/restart
### ===============================
up() {
  ensure_network
  pull_images

  # Collector
  rm_if_exists sage-collector
  log "[i] run: collector"
  docker run -d --restart unless-stopped --name sage-collector \
    --network "$STACK_NET" \
    $(port_args "sage-collector") \
    $(aws_env_args) \
    "$IMG_COLLECTOR"

  # Compliance Show
  rm_if_exists sage-compliance-show
  log "[i] run: compliance-show"
  docker run -d --restart unless-stopped --name sage-compliance-show \
    --network "$STACK_NET" \
    $(port_args "sage-compliance-show") \
    "$IMG_SHOW"

  # Compliance Audit
  rm_if_exists sage-compliance-audit
  log "[i] run: compliance-audit"
  docker run -d --restart unless-stopped --name sage-compliance-audit \
    --network "$STACK_NET" \
    $(port_args "sage-compliance-audit") \
    -e MAPPING_BASE_URL="http://sage-compliance-show:${IN_SHOW}" \
    -e COLLECTOR_BASE_URL="http://sage-collector:${IN_COLLECTOR}" \
    $(aws_env_args) \
    "$IMG_AUDIT"

  # Analyzer
  rm_if_exists sage-analyzer
  log "[i] run: analyzer"
  mkdir -p ./analyzer-data || true
  docker run -d --restart unless-stopped --name sage-analyzer \
    --network "$STACK_NET" \
    $(port_args "sage-analyzer") \
    -v "$(pwd)/analyzer-data:/app/var/results" \
    -e COLLECTOR_API="http://sage-collector:${IN_COLLECTOR}" \
    $(aws_env_args) \
    "$IMG_ANALYZER"

  # Lineage
  rm_if_exists sage-lineage
  log "[i] run: lineage"
  docker run -d --restart unless-stopped --name sage-lineage \
    --network "$STACK_NET" \
    $(port_args "sage-lineage") \
    $(aws_env_args) \
    "$IMG_LINEAGE"

  # Dashboard (Nginx)
  rm_if_exists sage-dashboard
  log "[i] run: dashboard"
  docker run -d --restart unless-stopped --name sage-dashboard \
    --network "$STACK_NET" \
    $(port_args "sage-dashboard") \
    "$IMG_DASHBOARD"

  # 간단한 준비 확인(대시보드만 체크)
  if [[ "$EXPOSE_BACKENDS" == "1" ]]; then
    wait_http_ok "127.0.0.1" "$DASHBOARD_PORT" "/" 20 || true
  else
    wait_http_ok "127.0.0.1" "$DASHBOARD_PORT" "/" 20 || true
  fi

  log ""
  log "✅ UP! 끝났어요."
  log "    dashboard          → http://localhost:${DASHBOARD_PORT}"
  if [[ "$EXPOSE_BACKENDS" == "1" ]]; then
    log "    analyzer API       → http://localhost:${ANALYZER_PORT}"
    log "    lineage API        → http://localhost:${LINEAGE_PORT}"
    log "    collector API      → http://localhost:${COLLECTOR_PORT}"
    log "    compliance-show    → http://localhost:${SHOW_PORT}"
    log "    compliance-audit   → http://localhost:${AUDIT_PORT}"
  else
    log "    (백엔드는 프록시 전용, 외부 미노출)"
  fi
}

down() {
  log "[i] stop & remove containers"
  docker rm -f \
    sage-dashboard \
    sage-lineage \
    sage-analyzer \
    sage-collector \
    sage-compliance-audit \
    sage-compliance-show 2>/dev/null || true

  log "✅ DOWN! 컨테이너 정리 완료."
}

logs_cmd() {
  local name="${1:-sage-dashboard}"
  log "[i] logs: $name (Ctrl+C to exit)"
  docker logs -f "$name"
}

restart_cmd() {
  local name="${1:-sage-dashboard}"
  log "[i] restart: $name"
  docker restart "$name"
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep "$name" || true
}

status_cmd() {
  status_table
}

ps_cmd() {
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
}

curl_cmd() {
  # curl_cmd <service-alias> [path] [host-expose]
  # service-alias: dashboard|collector|show|audit|analyzer|lineage
  local svc="${1:-dashboard}"
  local path="${2:-/}"
  local expose="${3:-1}"  # 1: host로 접속, 0: 컨테이너명으로 접속(docker exec 필요)
  local host port
  case "$svc" in
    dashboard) host="127.0.0.1"; port="$DASHBOARD_PORT" ;;
    collector) host="127.0.0.1"; port="$COLLECTOR_PORT" ;;
    show)      host="127.0.0.1"; port="$SHOW_PORT" ;;
    audit)     host="127.0.0.1"; port="$AUDIT_PORT" ;;
    analyzer)  host="127.0.0.1"; port="$ANALYZER_PORT" ;;
    lineage)   host="127.0.0.1"; port="$LINEAGE_PORT" ;;
    *)
      log "[err] unknown service: $svc"; exit 1 ;;
  esac

  if [[ "$svc" != "dashboard" && "$EXPOSE_BACKENDS" == "0" && "$expose" == "1" ]]; then
    log "[warn] EXPOSE_BACKENDS=0 상태에서는 백엔드가 외부에 노출되지 않습니다."
    log "       컨테이너 내부에서 테스트하려면: docker exec -it sage-dashboard sh (또는 알맞은 컨테이너)"
    exit 0
  fi

  curl -i "http://${host}:${port}${path}"
}

### ===============================
### CLI
### ===============================
usage() {
  cat <<-USAGE
  사용법:
    $(basename "$0") up                 # 전체 스택 실행 (이미지 pull 포함)
    $(basename "$0") down               # 전체 스택 중지/삭제
    $(basename "$0") logs [name]        # 특정 컨테이너 로그 (기본: sage-dashboard)
    $(basename "$0") restart [name]     # 특정 컨테이너 재시작
    $(basename "$0") status             # 상태 테이블
    $(basename "$0") ps                 # docker ps 요약
    $(basename "$0") curl <svc> [path]  # 로컬 노출된 포트로 HTTP 요청 (svc: dashboard|collector|show|audit|analyzer|lineage)

  환경변수:
    EXPOSE_BACKENDS=${EXPOSE_BACKENDS}     # 0이면 백엔드 미노출(프록시 전용), 1이면 포트 노출
    STACK_NET=${STACK_NET}
    USE_AWS_VOLUME=${USE_AWS_VOLUME}       # 1이면 ~/.aws 마운트, 0이면 ENV 전달
    AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}

    DASHBOARD_PORT=${DASHBOARD_PORT}
    LINEAGE_PORT=${LINEAGE_PORT}
    ANALYZER_PORT=${ANALYZER_PORT}
    COLLECTOR_PORT=${COLLECTOR_PORT}
    SHOW_PORT=${SHOW_PORT}
    AUDIT_PORT=${AUDIT_PORT}

  예:
    USE_AWS_VOLUME=1 EXPOSE_BACKENDS=0 ./$0 up
    DASHBOARD_PORT=8080 ANALYZER_PORT=8401 ./$0 up
    ./$0 logs sage-collector
    ./$0 curl dashboard /
USAGE
}

cmd="${1:-}"
case "$cmd" in
  up) up ;;
  down) down ;;
  logs) logs_cmd "${2:-sage-dashboard}" ;;
  restart) restart_cmd "${2:-sage-dashboard}" ;;
  status) status_cmd ;;
  ps) ps_cmd ;;
  curl) curl_cmd "${2:-dashboard}" "${3:-/}" ;;
  ""|-h|--help|help) usage ;;
  *)
    log "[err] unknown command: $cmd"
    usage
    exit 1
    ;;
esac
