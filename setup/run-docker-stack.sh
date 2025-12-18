#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.marketplace.yml"
ENV_FILE="${ROOT_DIR}/.sage-stack.env"
COMPOSE_BIN=()
DOCKER_PREFIX=()
AI_PROFILE_ENABLED=0

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "[$(date '+%H:%M:%S')] ❌ $*" >&2; exit 1; }

install_docker_stack() {
  log "Docker / Compose가 없어 자동 설치를 시도합니다."
  command -v sudo >/dev/null 2>&1 || die "sudo가 필요합니다. sudo 설치 또는 root 권한으로 실행해 주세요."
  if ! command -v curl >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y curl
  fi

  if ! command -v docker >/dev/null 2>&1; then
    log "Docker 엔진 설치 스크립트를 실행합니다."
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
  fi

  install_compose_cli

  sudo systemctl enable --now docker >/dev/null 2>&1 || true
  if ! groups "$(whoami)" | grep -qE '\bdocker\b'; then
    log "현재 사용자를 docker 그룹에 추가합니다 (다음 로그인부터 적용)."
    sudo usermod -aG docker "$(whoami)" || true
  fi
  log "Docker 설치가 완료되었습니다. 현재 세션에서는 'sudo docker' 사용이 필요할 수 있습니다."
}

install_compose_cli() {
  if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    log "docker-compose-plugin 패키지를 설치합니다."
    if sudo apt-get update -y && sudo apt-get install -y docker-compose-plugin; then
      return
    fi
    log "패키지 설치 실패 → standalone docker-compose 바이너리를 설치합니다."
  fi

  local target="/usr/local/bin/docker-compose"
  local url="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
  log "Downloading docker-compose binary from ${url}"
  sudo curl -L "${url}" -o "${target}"
  sudo chmod +x "${target}"
  log "docker-compose 바이너리 설치 완료 (${target})"
}

ensure_requirements() {
  if ! command -v docker >/dev/null 2>&1 || { ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; }; then
    install_docker_stack
  fi
  command -v docker >/dev/null 2>&1 || die "docker 명령을 찾을 수 없습니다. 수동 설치 후 다시 시도해 주세요."
  set_docker_access
  set_compose_bin
}

set_docker_access() {
  DOCKER_PREFIX=()
  if docker info >/dev/null 2>&1; then
    return
  fi

  if command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=(sudo)
    log "현재 세션에서는 sudo 권한으로 Docker를 실행합니다."
    return
  fi

  die "docker 데몬에 연결할 수 없습니다. sudo docker info 명령으로 확인해 주세요."
}

set_compose_bin() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_BIN=("${DOCKER_PREFIX[@]}" docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_BIN=("${DOCKER_PREFIX[@]}" docker-compose)
  else
    install_docker_stack
    set_docker_access
    if docker compose version >/dev/null 2>&1; then
      COMPOSE_BIN=("${DOCKER_PREFIX[@]}" docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
      COMPOSE_BIN=("${DOCKER_PREFIX[@]}" docker-compose)
    else
      die "docker compose CLI를 찾을 수 없습니다. docker compose 또는 docker-compose 중 하나가 필요합니다."
    fi
  fi
}

detect_ai_profile() {
  # docker compose는 COMPOSE_PROFILES 환경변수(콤마/공백/콜론 구분)를 사용해 profile을 선택한다.
  local profiles="${COMPOSE_PROFILES:-}"
  profiles="${profiles// /,}"
  profiles="${profiles//:/,}"
  case ",${profiles}," in
    *",ai,"*) AI_PROFILE_ENABLED=1 ;;
    *) AI_PROFILE_ENABLED=0 ;;
  esac
}

detect_ip() {
  local detected="${SAGE_HOST_IP:-}"
  if [ -z "$detected" ]; then
    detected="$(curl -fsS --max-time 3 ifconfig.me 2>/dev/null || true)"
  fi
  if [ -z "$detected" ]; then
    detected="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if [ -z "$detected" ]; then
    die "서버 공인 IP를 자동으로 찾지 못했습니다. SAGE_HOST_IP 환경 변수를 직접 설정해 주세요."
  fi
  echo "$detected"
}

write_env_file() {
  local host_ip="$1"
  local aws_region="${AWS_REGION:-ap-northeast-2}"

  local front_port="${FRONT_PORT:-8200}"
  local analyzer_port="${ANALYZER_PORT:-9000}"
  local collector_port="${COLLECTOR_PORT:-8000}"
  local com_show_port="${COM_SHOW_PORT:-8003}"
  local com_audit_port="${COM_AUDIT_PORT:-8103}"
  local lineage_port="${LINEAGE_PORT:-8300}"
  local oss_port="${OSS_PORT:-8800}"
  local ai_port="${AI_PORT:-8900}"
  local oss_workdir="${OSS_WORKDIR:-/workspace}"
  local pii_model_url="${PII_MODEL_URL:-http://sage-ai:8900/infer}"

  # Steampipe runs in the collector container; default to loopback so Linux hosts
  # don't depend on host.docker.internal being available.
  local steampipe_host="${STEAMPIPE_DB_HOST:-127.0.0.1}"
  local steampipe_port="${STEAMPIPE_DB_PORT:-9193}"
  local steampipe_user="${STEAMPIPE_DB_USER:-steampipe}"
  local steampipe_name="${STEAMPIPE_DB_NAME:-steampipe}"

  local base="http://${host_ip}"
  local front_url="${base}:${front_port}"
  local analyzer_url="${base}:${analyzer_port}"
  local collector_url="${base}:${collector_port}"
  local com_show_url="${base}:${com_show_port}"
  local com_audit_url="${base}:${com_audit_port}"
  local lineage_url="${base}:${lineage_port}"
  local oss_url="${base}:${oss_port}"
  local ai_url="${base}:${ai_port}"

  cat > "${ENV_FILE}" <<EOF
# 자동 생성 파일 - 필요 시 setup/run-docker-stack.sh를 재실행하세요.
HOST_IP=${host_ip}
PUBLIC_BASE=${base}
FRONT_PORT=${front_port}
ANALYZER_PORT=${analyzer_port}
COLLECTOR_PORT=${collector_port}
COM_SHOW_PORT=${com_show_port}
COM_AUDIT_PORT=${com_audit_port}
LINEAGE_PORT=${lineage_port}
OSS_PORT=${oss_port}
AI_PORT=${ai_port}
FRONT_URL=${front_url}
ANALYZER_URL=${analyzer_url}
COLLECTOR_URL=${collector_url}
COM_SHOW_URL=${com_show_url}
COM_AUDIT_URL=${com_audit_url}
LINEAGE_URL=${lineage_url}
OSS_URL=${oss_url}
AI_URL=${ai_url}
AWS_REGION=${aws_region}
STEAMPIPE_DB_HOST=${steampipe_host}
STEAMPIPE_DB_PORT=${steampipe_port}
STEAMPIPE_DB_USER=${steampipe_user}
STEAMPIPE_DB_NAME=${steampipe_name}
REACT_APP_API_HOST=${host_ip}
REACT_APP_AEGIS_API_BASE=${analyzer_url}
REACT_APP_COLLECTOR_API_BASE=${collector_url}
REACT_APP_INVENTORY_API_BASE=${collector_url}
REACT_APP_COMPLIANCE_API_BASE=${com_show_url}
REACT_APP_AUDIT_API_BASE=${com_audit_url}
REACT_APP_LINEAGE_API_BASE=${lineage_url}
REACT_APP_OSS_BASE=${oss_url}/oss
REACT_APP_OSS_WORKDIR=${oss_workdir}
SAGE_FRONT_IMAGE=${SAGE_FRONT_IMAGE:-comnyang/sage-front:latest}
SAGE_ANALYZER_IMAGE=${SAGE_ANALYZER_IMAGE:-comnyang/sage-analyzer:latest}
SAGE_COLLECTOR_IMAGE=${SAGE_COLLECTOR_IMAGE:-comnyang/sage-collector@sha256:f0a762b0163c27bb1f2bde806dd7cde858539f58bacd05ba3c1298d78fadba4c}
SAGE_COM_SHOW_IMAGE=${SAGE_COM_SHOW_IMAGE:-comnyang/sage-com-show:latest}
SAGE_COM_AUDIT_IMAGE=${SAGE_COM_AUDIT_IMAGE:-comnyang/sage-com-audit:latest}
SAGE_LINEAGE_IMAGE=${SAGE_LINEAGE_IMAGE:-comnyang/sage-lineage:latest}
SAGE_OSS_IMAGE=${SAGE_OSS_IMAGE:-comnyang/sage-oss:latest}
SAGE_AI_IMAGE=${SAGE_AI_IMAGE:-comnyang/sage-ai:latest}
SAGE_HOST=${host_ip}
PII_MODEL_URL=${pii_model_url}
EOF
}

bring_up_stack() {
  log "이미지 풀 및 컨테이너 기동 (환경 파일: ${ENV_FILE})"
  if [ "${AI_PROFILE_ENABLED}" -eq 0 ]; then
    log "AI 서비스는 기본 비활성화 상태입니다. 활성화하려면 COMPOSE_PROFILES=ai ./setup.sh 형태로 실행하세요."
  fi
  "${COMPOSE_BIN[@]}" --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" pull
  "${COMPOSE_BIN[@]}" --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d --remove-orphans
}

print_summary() {
  cat <<EOF

SAGE Docker 스택 기동 완료 ✅

 - Frontend:            ${FRONT_URL}
 - Analyzer API:        ${ANALYZER_URL}
 - Data Collector API:  ${COLLECTOR_URL}
 - Compliance-show API: ${COM_SHOW_URL}
 - Compliance-audit:    ${COM_AUDIT_URL}
 - Lineage API:         ${LINEAGE_URL}
 - OSS Runner API:      ${OSS_URL}
 - AI API:              $(if [ "${AI_PROFILE_ENABLED}" -eq 1 ]; then echo "${AI_URL}"; else echo "비활성화 (COMPOSE_PROFILES=ai 로 활성화)"; fi)

docker compose down 시:
  ${COMPOSE_BIN[*]} --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" down

환경 수정 시:
  1) 필요 변수 수정을 위해 ${ENV_FILE}를 편집하거나
  2) env를 비우고 setup/run-docker-stack.sh를 다시 실행
EOF
}

main() {
  ensure_requirements
  [ -f "${COMPOSE_FILE}" ] || die "구성 파일(${COMPOSE_FILE})을 찾을 수 없습니다."
  detect_ai_profile

  local ip
  ip="$(detect_ip)"
  log "서버 공인 IP: ${ip}"

  write_env_file "${ip}"
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
  bring_up_stack
  print_summary
}

main "$@"
