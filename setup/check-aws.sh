#!/usr/bin/env bash
# check-aws.sh
# 목적: (1) 필수 패키지 설치 → (2) AWS CLI 설치/검증 → (3) 필요 시 aws configure 인터랙티브 입력
#      (4) Steampipe 설치/실행 → (5) DSPM_Data-Collector 클론 → (6) API 0.0.0.0:8000 백그라운드 기동
# 사용법: 환경변수 없이 그냥 ./setup/check-aws.sh 실행 (configure 단계에서만 입력 받음)

set -euo pipefail

### ===== 기본 설정(변수 입력 불필요) =====
REPO_URL="https://github.com/BOB-DSPM/DSPM_Data-Collector.git"
BRANCH="main"
TARGET_DIR="DSPM_Data-Collector"

API_HOST="0.0.0.0"
API_PORT="8000"
AWS_PROFILE="default"      # 기본 프로파일 이름 (변경 필요 없음)
FORCE_AWS_CONFIG="0"       # 0: 자격증명 유효하면 묻지 않음 / 1: 항상 재설정

### ===== 출력 유틸 =====
log()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

### ===== 권한/패키지 관리자 =====
SUDO=""; if [ "${EUID:-$(id -u)}" -ne 0 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  if command -v dnf      >/dev/null 2>&1; then echo "dnf"; return; fi
  if command -v yum      >/dev/null 2>&1; then echo "yum"; return; fi
  if command -v pacman   >/dev/null 2>&1; then echo "pacman"; return; fi
  if command -v zypper   >/dev/null 2>&1; then echo "zypper"; return; fi
  if command -v brew     >/dev/null 2>&1; then echo "brew"; return; fi
  echo "unknown"
}

check_net() {
  if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 || curl -s --max-time 3 https://github.com >/dev/null 2>&1; then return 0; fi
  warn "네트워크 불안정 — 설치/클론 실패 가능"
}

### ===== 필수 패키지 보장 (curl, unzip, tar, gzip, lsof, ca-certificates) =====
ensure_packages() {
  local pm; pm="$(detect_pm)"
  check_net || true

  # 각 커맨드 존재 여부 확인 후 패키지 이름 매핑
  need_pkgs=()

  # curl
  command -v curl >/dev/null 2>&1 || need_pkgs+=("curl")
  # unzip
  command -v unzip >/dev/null 2>&1 || need_pkgs+=("unzip")
  # lsof
  command -v lsof >/dev/null 2>&1 || need_pkgs+=("lsof")
  # tar
  command -v tar >/dev/null 2>&1 || need_pkgs+=("tar")
  # gzip
  command -v gzip >/dev/null 2>&1 || need_pkgs+=("gzip")
  # ca-certificates (맥은 생략)
  if [ "$pm" != "brew" ]; then
    [ -f /etc/ssl/certs/ca-certificates.crt ] || need_pkgs+=("ca-certificates")
  fi

  if [ "${#need_pkgs[@]}" -eq 0 ]; then
    ok "필수 패키지 이미 설치됨"
    return
  fi

  log "필수 패키지 설치: ${need_pkgs[*]}"
  case "$pm" in
    apt)
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y
      # tar/gzip은 기본 설치지만 누락 대비 포함
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "${need_pkgs[@]}"
      ;;
    dnf|yum)
      $SUDO "$pm" install -y "${need_pkgs[@]}"
      ;;
    pacman)
      $SUDO pacman -Sy --noconfirm "${need_pkgs[@]}"
      ;;
    zypper)
      $SUDO zypper --non-interactive refresh
      $SUDO zypper --non-interactive install "${need_pkgs[@]}"
      ;;
    brew)
      # macOS: 기본적으로 curl/tar/gzip 있음. 없을 수 있는 unzip/lsof만 처리.
      for p in "${need_pkgs[@]}"; do
        case "$p" in
          unzip|lsof|curl) brew list --versions "$p" >/dev/null 2>&1 || brew install "$p" ;;
          *) : ;; # tar/gzip/ca-certificates는 보통 불필요
        esac
      done
      ;;
    *)
      err "패키지 매니저를 인식하지 못했습니다. 필수 패키지를 수동 설치하세요."
      exit 1
      ;;
  esac
  ok "필수 패키지 설치 완료"
}

### ===== 공통 보장 도구 =====
ensure_git() {
  if command -v git >/dev/null 2>&1; then ok "git: $(git --version)"; return; fi
  local pm; pm="$(detect_pm)"; check_net || true
  case "$pm" in
    apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y git ;;
    dnf)    $SUDO dnf install -y git ;;
    yum)    $SUDO yum install -y git ;;
    pacman) $SUDO pacman -Sy --noconfirm git ;;
    zypper) $SUDO zypper --non-interactive refresh; $SUDO zypper --non-interactive install git ;;
    brew)   brew update; brew install git ;;
    *)      err "패키지 매니저를 인식하지 못했습니다. Git 수동 설치 필요."; exit 1 ;;
  esac
  ok "git 설치 완료: $(git --version)"
}

ensure_python() {
  if command -v python3 >/dev/null 2>&1; then ok "python3: $(python3 --version)"; return; fi
  local pm; pm="$(detect_pm)"; check_net || true
  case "$pm" in
    apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y python3 python3-venv python3-pip ;;
    dnf|yum)$SUDO "${pm}" install -y python3 python3-pip ;;
    pacman) $SUDO pacman -Sy --noconfirm python python-pip ;;
    zypper) $SUDO zypper --non-interactive install python3 python3-pip python3-venv || $SUDO zypper --non-interactive install python311 python311-pip ;;
    brew)   brew update; brew install python ;;
    *)      err "Python 설치 불가한 환경입니다. 수동 설치 필요."; exit 1 ;;
  esac
  ok "python3 설치 완료: $(python3 --version)"
}

### ===== AWS CLI 설치 & 구성 =====
install_awscli() {
  check_net || true
  local os="$(uname -s)" arch="$(uname -m)"
  if [ "$os" = "Darwin" ] && command -v brew >/dev/null 2;&1; then
    log "Homebrew로 AWS CLI 설치"; brew update; brew install awscli; return
  fi
  local url=""
  case "$arch" in
    x86_64|amd64) url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
    aarch64|arm64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
    *)
      warn "알 수 없는 아키텍처(${arch}) → 패키지 매니저로 설치 시도"
      local pm; pm="$(detect_pm)"
      case "$pm" in
        apt)    $SUDO apt-get update -y; $SUDO apt-get install -y awscli ;;
        dnf|yum)$SUDO "$pm" install -y awscli ;;
        pacman) $SUDO pacman -Sy --noconfirm aws-cli ;;
        zypper) $SUDO zypper --non-interactive install aws-cli ;;
        *)      err "AWS CLI 설치 방법을 결정하지 못했습니다."; exit 1 ;;
      esac
      return;;
  esac
  log "AWS CLI v2 설치 (공식 패키지)"
  tmpd="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmpd/awscliv2.zip"
  unzip -q "$tmpd/awscliv2.zip" -d "$tmpd"
  if [ -n "$SUDO" ]; then
    $SUDO "$tmpd/aws/install" --update
  else
    mkdir -p "$HOME/.local/aws-cli"
    "$tmpd/aws/install" -i "$HOME/.local/aws-cli" -b "$HOME/.local/bin" --update
    export PATH="$HOME/.local/bin:$PATH"
  fi
  rm -rf "$tmpd"
}

ensure_awscli() {
  if command -v aws >/dev/null 2>&1; then ok "aws: $(aws --version 2>&1 | head -n1)"; return; fi
  log "AWS CLI 미설치 — 설치 진행"; install_awscli
  command -v aws >/dev/null 2>&1 || { err "AWS CLI 설치 실패"; exit 1; }
  ok "aws: $(aws --version 2>&1 | head -n1)"
}

configure_aws_if_needed() {
  local need="$FORCE_AWS_CONFIG"
  if [ "$need" = "0" ] && aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    ok "유효한 AWS 자격증명 확인됨(프로파일: $AWS_PROFILE) — configure 생략"; return 0
  fi
  warn "AWS 자격증명이 필요합니다. 값을 입력해 주세요. (입력은 로컬에만 저장됩니다)"

  echo
  echo "=== aws configure (${AWS_PROFILE}) ==="
  read -rp "AWS Access Key ID: " AKID
  read -srp "AWS Secret Access Key: " SAK; echo
  read -rp "Default region name [ap-northeast-2]: " REGION; REGION="${REGION:-ap-northeast-2}"
  read -rp "Default output format [json]: " OUTF; OUTF="${OUTF:-json}"
  read -rp "AWS Session Token (있으면 입력/없으면 엔터): " STOK || true

  aws configure set aws_access_key_id "$AKID" --profile "$AWS_PROFILE"
  aws configure set aws_secret_access_key "$SAK" --profile "$AWS_PROFILE"
  [ -n "${STOK:-}" ] && aws configure set aws_session_token "$STOK" --profile "$AWS_PROFILE" || true
  aws configure set region "$REGION" --profile "$AWS_PROFILE"
  aws configure set output "$OUTF" --profile "$AWS_PROFILE"

  if aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    ok "AWS 자격증명 설정 완료(프로파일: $AWS_PROFILE)"
  else
    err "AWS 자격증명 검증 실패 — 키/권한/네트워크 확인 필요"; exit 1
  fi
}

### ===== Steampipe 설치/실행 =====
ensure_steampipe() {
  export PATH="$HOME/.local/bin:$HOME/.steampipe/bin:$PATH"
  if command -v steampipe >/dev/null 2>&1; then ok "steampipe: $(steampipe -v | head -n1)"; else
    check_net || true
    local dest; dest="/usr/local/bin"
    if [ -n "$SUDO" ]; then
      log "Steampipe 설치 → ${dest} (sudo)"
      if ! curl -fsSL https://steampipe.io/install/steampipe.sh | $SUDO bash -s -- -b "$dest"; then
        warn "공식 스크립트 실패 → GitHub raw로 재시도(sudo)"
        curl -fsSL https://raw.githubusercontent.com/turbot/steampipe/main/scripts/install.sh | $SUDO bash -s -- -b "$dest"
      fi
    else
      dest="$HOME/.local/bin"; mkdir -p "$dest"
      log "Steampipe 설치 → ${dest} (user)"
      if ! curl -fsSL https://steampipe.io/install/steampipe.sh | bash -s -- -b "$dest"; then
        warn "공식 스크립트 실패 → GitHub raw로 재시도(user)"
        curl -fsSL https://raw.githubusercontent.com/turbot/steampipe/main/scripts/install.sh | bash -s -- -b "$dest"
      fi
    end
    export PATH="$dest:$HOME/.local/bin:$HOME/.steampipe/bin:$PATH"
    command -v steampipe >/dev/null 2>&1 || { err "steampipe 설치 실패"; exit 1; }
    ok "steampipe: $(steampipe -v | head -n1)"
  fi

  if steampipe plugin list 2>/dev/null | grep -q '^aws'; then
    ok "steampipe aws 플러그인 설치됨"
  else
    log "steampipe aws 플러그인 설치"; steampipe plugin install aws
  fi

  if steampipe service status 2>/dev/null | grep -qi "running"; then
    ok "steampipe service 이미 실행 중"
  else
    log "steampipe service start"; steampipe service start
    steampipe service status >/dev/null 2>&1 || { err "steampipe service 기동 실패"; exit 1; }
    ok "steampipe service 실행"
  fi
}

### ===== 레포 클론/업데이트 + API 기동(백그라운드) =====
clone_or_update() {
  if [ -d "$TARGET_DIR/.git" ]; then
    log "레포 업데이트: $TARGET_DIR"
    git -C "$TARGET_DIR" fetch --all --prune
    git -C "$TARGET_DIR" checkout "$BRANCH"
    git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH" || git -C "$TARGET_DIR" pull --rebase origin "$BRANCH"
  else
    if [ -e "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR/.git" ]; then
      ts="$(date +%Y%m%d-%H%M%S)"; mv "$TARGET_DIR" "${TARGET_DIR}.bak-${ts}"; warn "동명 폴더 백업함"
    fi
    log "레포 클론: $REPO_URL → $TARGET_DIR"
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
  fi
  ok "레포 준비 완료: $TARGET_DIR"
}

run_api_bg() {
  cd "$TARGET_DIR"
  mkdir -p logs
  if [ -f ".pid" ]; then
    old_pid="$(cat .pid || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
      warn "기존 API 실행 감지(PID=${old_pid}) → 종료 후 재시작"
      kill "$old_pid" || true; sleep 1
    fi
  fi

  if [ ! -d ".venv" ]; then log "Python venv 생성(.venv)"; python3 -m venv .venv; fi
  # shellcheck disable=SC1091
  . ".venv/bin/activate"
  python -m pip install --upgrade pip >/dev/null
  if [ -f "requirements.txt" ]; then
    log "requirements 설치"; pip install -r requirements.txt
  else
    log "requirements.txt 없음 → 최소 패키지 설치"; pip install fastapi uvicorn steampipe
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  logfile="logs/collector-api-${ts}.log"
  ok "Collector API 백그라운드 시작: HOST=${API_HOST} PORT=${API_PORT}"
  HOST="${API_HOST}" PORT="${API_PORT}" nohup python -m uvicorn main:app --host "${API_HOST}" --port "${API_PORT}" --reload >"${logfile}" 2>&1 &
  echo "$!" > .pid
  ok "PID=$(cat .pid) (로그: ${logfile})"
  log "로그: tail -f ${logfile}"
  log "중지: kill \$(cat .pid)"
}

### ===== 엔트리포인트 =====
main() {
  check_net || true
  ensure_packages      # <-- 필수 패키지 먼저 확보!
  ensure_git
  ensure_python
  ensure_awscli
  configure_aws_if_needed   # <-- 이 단계에서만 사용자 입력을 받음
  ensure_steampipe
  clone_or_update
  run_api_bg
}
main "$@"
