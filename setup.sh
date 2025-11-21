#!/usr/bin/env bash
set -euo pipefail

# 간단한 Docker 스택 부트스트랩: 다른 설치 스크립트 호출 없이
# setup/run-docker-stack.sh 하나만 실행한다.

if [ -t 1 ]; then
  GREEN="$(printf '\033[32m')"; BOLD="$(printf '\033[1m')"; RESET="$(printf '\033[0m')"
else
  GREEN=""; BOLD=""; RESET=""
fi

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
step() { echo; log "${BOLD}▶ $*${RESET}"; }
ok()   { log "${GREEN}✅ $*${RESET}"; }
die()  { echo "[$(date '+%H:%M:%S')] ❌ $*" >&2; exit 1; }

ensure_in_repo_root() {
  [ -d "setup" ] || die "현재 디렉토리에 'setup' 폴더가 없습니다. SAGE 리포 루트에서 실행해 주세요."
}

run_docker_stack() {
  local script="./setup/run-docker-stack.sh"
  [ -x "$script" ] || chmod +x "$script"
  step "SAGE Docker 스택을 기동합니다"
  "$script"
}

main() {
  ensure_in_repo_root
  run_docker_stack
  ok "SAGE Docker 스택 셋업이 완료되었습니다."
}

main "$@"
