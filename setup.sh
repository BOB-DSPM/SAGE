#!/usr/bin/env bash
set -euo pipefail

# ==========================
#  SAGE All-in-One Bootstrap
# ==========================

# ─ 색상 설정 ─
if [ -t 1 ]; then
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  BOLD="$(printf '\033[1m')"
  RESET="$(printf '\033[0m')"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

log()   { echo -e "[$(date '+%H:%M:%S')] $*"; }
info()  { log "${BLUE}ℹ️  $*${RESET}"; }
ok()    { log "${GREEN}✅ $*${RESET}"; }
warn()  { log "${YELLOW}⚠️  $*${RESET}"; }
err()   { log "${RED}❌ $*${RESET}"; }

step()  {
  echo ""
  log "${BOLD}▶ $*${RESET}"
}

run_step() {
  local title="$1"; shift
  step "$title"
  if "$@"; then
    ok "$title 완료"
  else
    err "$title 실패"
    exit 1
  fi
}

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    warn "'$c' 명령을 찾을 수 없습니다."
    return 1
  fi
  return 0
}

ensure_root_tools() {
  step "기본 패키지 설치 (curl, unzip, git, lsof, wget, tar)"
  sudo apt update -y
  sudo apt install -y curl unzip git lsof wget tar
  ok "기본 패키지 설치 완료"
}

ensure_in_repo_root() {
  if [ ! -d "setup" ]; then
    err "현재 디렉토리에 'setup' 폴더가 없습니다. SAGE 리포 루트에서 실행해 주세요."
    exit 1
  fi
}

make_setup_executable() {
  step "setup 스크립트 실행 권한 부여"
  chmod +x ./setup/*
  ok "실행 권한 부여 완료"
}

print_banner() {
  cat <<EOF

${BOLD}======================================================
   SAGE 환경 통합 설치 / 재기동 스크립트
======================================================${RESET}

 - AWS CLI, Python, Node.js, Steampipe 등 기본 도구 설치
 - SAGE 백엔드 서비스 자동 설치 및 기동
   * Analyzer (port 9000)
   * Data Collector (port 8000)
   * Compliance-show (port 8003)
   * Compliance-audit (port 8103)
   * Lineage Tracking (port 8300)
   * Opensource Runner (port 8800)
   * Identity-AI (port 8900)
 - Frontend (SAGE-FRONT, port 8200) 빌드 및 기동

${YELLOW}※ 주의:${RESET}
 - 최초 1회는 AWS 자격 증명(Access Key 등)을 별도로
   'aws configure'로 설정해야 AWS 리소스 스캔이 정상 동작합니다.
 - 이 스크립트를 실행하면 위 포트들을 점유 중인 기존 프로세스는
   자동으로 종료(kill)됩니다.

EOF
}

confirm_start() {
  read -r -p "$(echo -e "${BOLD}SAGE 전체 환경을 설치/재기동 할까요? (y/N): ${RESET}")" ans
  case "$ans" in
    y|Y|yes|YES)
      ok "설치를 시작합니다."
      ;;
    *)
      warn "사용자가 설치를 취소했습니다."
      exit 0
      ;;
  esac
}

install_aws_cli() {
  if require_cmd aws; then
    info "AWS CLI가 이미 설치되어 있습니다. (건너뜀)"
    return 0
  fi

  step "AWS CLI v2 설치"
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -o awscliv2.zip
  sudo ./aws/install
  rm -rf aws awscliv2.zip
  ok "AWS CLI 설치 완료"

  warn "AWS 자격 증명은 별도로 'aws configure'로 한 번만 설정해 주세요."
}

install_python_node() {
  step "Python / Node.js / npm 설치"
  sudo apt update -y
  sudo apt install -y python3.11 python3-pip python3-venv nodejs npm
  ok "Python / Node.js / npm 설치 완료"
}

install_steampipe() {
  if require_cmd steampipe; then
    info "Steampipe가 이미 설치되어 있습니다. (건너뜀)"
  else
    step "Steampipe 설치"
    curl -sL https://steampipe.io/install.sh | bash
    ok "Steampipe 설치 완료"
  fi

  step "Steampipe AWS 플러그인 설치 및 서비스 시작"
  steampipe plugin install aws || true
  steampipe service start || true
  ok "Steampipe 서비스 준비 완료"
}

run_subscripts() {
  # 이 부분이 핵심: 사용자는 여기서 추가 입력 없이 쭉 진행됨.

  # 설치 계열
  run_step "AWS CLI 설치 (setup/install-aws.sh)"   sudo ./setup/install-aws.sh || install_aws_cli
  run_step "Python 환경 설치 (setup/install-python.sh)" sudo ./setup/install-python.sh || install_python_node
  run_step "Node.js / npm 설치 (setup/install-npm.sh)"  sudo ./setup/install-npm.sh || true

  # 공통 도구 (Steampipe 등)
  install_steampipe

  # 서비스 계열 (포트 정리 + git clone + venv + 서비스 기동)
  run_step "Frontend 설정 및 기동 (set-front.sh)"        ./setup/set-front.sh
  run_step "Data Collector 설정 및 기동 (set-collect.sh)" ./setup/set-collect.sh
  run_step "Lineage Tracking 설정 및 기동 (set-lineage.sh)" ./setup/set-lineage.sh
  run_step "Compliance-show 설정 및 기동 (set-com-show.sh)" ./setup/set-com-show.sh
  run_step "Compliance-audit 설정 및 기동 (set-com-audit.sh)" ./setup/set-com-audit.sh
  run_step "Opensource Runner 설정 및 기동 (set-oss.sh)" ./setup/set-oss.sh
  run_step "Analyzer 설정 및 기동 (set-analyzer.sh)"   ./setup/set-analyzer.sh
  run_step "Identity-AI 설정 및 기동 (set-ide-ai.sh)"  ./setup/set-ide-ai.sh
}

print_summary() {
  cat <<EOF

${BOLD}==========================================
   SAGE 설치 / 재기동이 완료되었습니다 🎉
==========================================${RESET}

접속 정보 (기본 포트):

 - Frontend (SAGE-FRONT): ${GREEN}http://<서버 IP>:8200${RESET}
 - Analyzer API:          http://<서버 IP>:9000
 - Data Collector API:    http://<서버 IP>:8000
 - Compliance-show API:   http://<서버 IP>:8003
 - Compliance-audit API:  http://<서버 IP>:8103
 - Lineage API:           http://<서버 IP>:8300
 - Opensource Runner:     http://<서버 IP>:8800
 - Identity-AI API:       http://<서버 IP>:8900

로그 파일(리포 루트 기준):

 - Analyzer:        DSPM_DATA-IC-analyzer/analyzer.log
 - Data Collector:  DSPM_Data-Collector/backend.log
 - Compliance-show: DSPM_Compliance-show/com-show.log
 - Compliance-audit:DSPM_Compliance-audit-fix/com-audit.log
 - Lineage:         DSPM_DATA-Lineage-Tracking/lineage.log
 - Opensource:      DSPM_Opensource-Runner/oss.log
 - Identity-AI:     SAGE_Identity-AI/iden-ai.log
 - Frontend:        SAGE-FRONT/dspm_dashboard/frontend.log

${YELLOW}※ AWS 계정 연결이 아직 안 되어 있다면:${RESET}
   아래 명령으로 한 번만 자격 증명을 설정해 주세요.

   ${BOLD}aws configure${RESET}

EOF
}

main() {
  print_banner
  ensure_in_repo_root
  ensure_root_tools
  make_setup_executable
  confirm_start
  run_subscripts
  print_summary
}

main "$@"
