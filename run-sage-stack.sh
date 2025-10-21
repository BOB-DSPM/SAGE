#!/usr/bin/env bash
set -euo pipefail

### ===============================
### 기본 포트 (원하면 바꿔서 실행)
### ===============================
DASHBOARD_PORT="${DASHBOARD_PORT:-3000}"   # comnyang/sage-dashboard (Nginx)
LINEAGE_PORT="${LINEAGE_PORT:-8300}"       # comnyang/sage-lineage
ANALYZER_PORT="${ANALYZER_PORT:-8400}"     # comnyang/sage-analyzer
COLLECTOR_PORT="${COLLECTOR_PORT:-8103}"   # comnyang/sage-collector
SHOW_PORT="${SHOW_PORT:-8003}"             # comnyang/sage-compliance-show
AUDIT_PORT="${AUDIT_PORT:-8104}"           # comnyang/sage-compliance-audit (collector와 포트 충돌 피하려고 8104로 설정)

### ===============================
### 공통 설정
### ===============================
STACK_NET="sage-net"

# AWS 크레덴셜 (선택 1: 환경변수로 전달)
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"
AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN:-}"            # 세션 사용하는 경우만
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"

# AWS 크레덴셜 (선택 2: 로컬 프로필 마운트) - 사용하려면 1로
USE_AWS_VOLUME="${USE_AWS_VOLUME:-0}"                 # 1이면 ~/.aws를 /root/.aws:ro로 마운트

### ===============================
### 이미지 이름
### ===============================
IMG_DASHBOARD="comnyang/sage-front:latest"
IMG_LINEAGE="comnyang/sage-lineage:latest"
IMG_ANALYZER="comnyang/sage-analyzer:latest"
IMG_COLLECTOR="comnyang/sage-collector:latest"
IMG_SHOW="comnyang/sage-compliance-show:latest"
IMG_AUDIT="comnyang/sage-compliance-audit:latest"

### ===============================
### 내부 포트 (컨테이너 안에서 노출되는 포트)
### ===============================
IN_DASHBOARD=3000
IN_LINEAGE=8300
IN_ANALYZER=8400
IN_COLLECTOR=8103
IN_SHOW=8003
IN_AUDIT=8103

### ===============================
### 도우미 함수
### ===============================
ensure_network() {
  if ! docker network inspect "$STACK_NET" >/dev/null 2>&1; then
    echo "[i] create network: $STACK_NET"
    docker network create "$STACK_NET"
  fi
}

aws_env_args() {
  if [[ "$USE_AWS_VOLUME" == "1" ]]; then
    echo "-v $HOME/.aws:/root/.aws:ro"
  else
    # 환경변수 방식
    echo "-e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
          ${AWS_SESSION_TOKEN:+-e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN} \
          -e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION"
  fi
}

pull_images() {
  echo "[i] pulling images..."
  docker pull "$IMG_DASHBOARD"
  docker pull "$IMG_LINEAGE"
  docker pull "$IMG_ANALYZER"
  docker pull "$IMG_COLLECTOR"
  docker pull "$IMG_SHOW"
  docker pull "$IMG_AUDIT"
}

up() {
  ensure_network
  pull_images

  echo "[i] run: collector"
  docker run -d --restart unless-stopped --name sage-collector \
    --network "$STACK_NET" \
    -p "${COLLECTOR_PORT}:${IN_COLLECTOR}" \
    $(aws_env_args) \
    "$IMG_COLLECTOR"

  echo "[i] run: compliance-show"
  docker run -d --restart unless-stopped --name sage-compliance-show \
    --network "$STACK_NET" \
    -p "${SHOW_PORT}:${IN_SHOW}" \
    "$IMG_SHOW"

  echo "[i] run: compliance-audit"
  docker run -d --restart unless-stopped --name sage-compliance-audit \
    --network "$STACK_NET" \
    -p "${AUDIT_PORT}:${IN_AUDIT}" \
    -e MAPPING_BASE_URL="http://sage-compliance-show:${IN_SHOW}" \
    -e COLLECTOR_BASE_URL="http://sage-collector:${IN_COLLECTOR}" \
    $(aws_env_args) \
    "$IMG_AUDIT"

  echo "[i] run: analyzer"
  # 결과 저장소 볼륨(옵션): ./analyzer-data -> 컨테이너 /app/var/results
  mkdir -p ./analyzer-data || true
  docker run -d --restart unless-stopped --name sage-analyzer \
    --network "$STACK_NET" \
    -p "${ANALYZER_PORT}:${IN_ANALYZER}" \
    -v "$(pwd)/analyzer-data:/app/var/results" \
    $(aws_env_args) \
    "$IMG_ANALYZER"

  echo "[i] run: lineage"
  docker run -d --restart unless-stopped --name sage-lineage \
    --network "$STACK_NET" \
    -p "${LINEAGE_PORT}:${IN_LINEAGE}" \
    $(aws_env_args) \
    "$IMG_LINEAGE"

  echo "[i] run: dashboard"
  docker run -d --restart unless-stopped --name sage-dashboard \
    --network "$STACK_NET" \
    -p "${DASHBOARD_PORT}:${IN_DASHBOARD}" \
    "$IMG_DASHBOARD"

  echo ""
  echo "✅ UP! 끝났어요."
  echo "    dashboard          → http://localhost:${DASHBOARD_PORT}  (또는 / )"
  echo "    analyzer API       → http://localhost:${ANALYZER_PORT}"
  echo "    lineage API        → http://localhost:${LINEAGE_PORT}"
  echo "    collector API      → http://localhost:${COLLECTOR_PORT}"
  echo "    compliance-show    → http://localhost:${SHOW_PORT}"
  echo "    compliance-audit   → http://localhost:${AUDIT_PORT}"
}

down() {
  echo "[i] stop & remove containers"
  docker rm -f sage-dashboard sage-lineage sage-analyzer sage-collector sage-compliance-audit sage-compliance-show 2>/dev/null || true

  # 네트워크는 남겨두고 싶으면 주석 처리
  # docker network rm "$STACK_NET" 2>/dev/null || true
  echo "✅ DOWN! 컨테이너 정리 완료."
}

logs() {
  docker logs -f "$1"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  logs) logs "${2:-sage-dashboard}" ;;
  *)
    cat <<-USAGE
    사용법:
      $(basename "$0") up        # 전체 스택 실행 (이미지 pull 포함)
      $(basename "$0") down      # 전체 스택 중지/삭제
      $(basename "$0") logs <name>  # 특정 컨테이너 로그 follow (기본: sage-dashboard)

    환경변수로 포트/옵션 조절:
      DASHBOARD_PORT=${DASHBOARD_PORT}
      LINEAGE_PORT=${LINEAGE_PORT}
      ANALYZER_PORT=${ANALYZER_PORT}
      COLLECTOR_PORT=${COLLECTOR_PORT}
      SHOW_PORT=${SHOW_PORT}
      AUDIT_PORT=${AUDIT_PORT}
      USE_AWS_VOLUME=${USE_AWS_VOLUME}   # 1이면 ~/.aws 마운트 사용
      AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}

    예:
      USE_AWS_VOLUME=1 ./$0 up
      DASHBOARD_PORT=8080 ANALYZER_PORT=8401 ./$0 up
USAGE
    ;;
esac
