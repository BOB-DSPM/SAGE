#!/usr/bin/env bash
# collector_setup.sh
# DSPM_Data-Collector 클론 → AWS CLI 설치/구성 → Steampipe 설치/실행 → Python API(uvicorn) 0.0.0.0:8000 백그라운드 기동
# 대상 OS: Ubuntu/Debian, RHEL/CentOS/Alma/Rocky, Amazon Linux, Fedora, Arch, openSUSE, macOS

set -euo pipefail

### ===== 설정 =====
REPO_URL="${REPO_URL:-https://github.com/BOB-DSPM/DSPM_Data-Collector.git}"
BRANCH="${BRANCH:-main}"
TARGET_DIR="${TARGET_DIR:-DSPM_Data-Collector}"

API_HOST="${HOST:-0.0.0.0}"
API_PORT="${PORT:-8000}"
FORCE_RESTART="${FORCE_RESTART:-1}"      # 1이면 기존 프로세스 종료 후 재시작
AWS_PROFILE="${AWS_PROFILE:-default}"    # aws configure 설정 대상 프로파일
FORCE_AWS_CONFIG="${FORCE_AWS_CONFIG:-0}"# 1이면 설정이 있어도 다시 묻고 설정

### ===== 출력 도우미 =====
log()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

### ===== 권한/패키지 관리자 =====
SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

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

### ===== Git 보장 =====
ensure_git() {
  if command -v git >/dev/null 2>&1; then ok "git: $(git --version)"; return; fi
  local pm; pm="$(detect_pm)"; check_net || true
  case "$pm" in
    apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y git ca-certificates curl unzip ;;
    dnf)    $SUDO dnf install -y git ca-certificates curl unzip ;;
    yum)    $SUDO yum install -y git ca-certificates curl unzip ;;
    pacman) $SUDO pacman -Sy --noconfirm git ca-certificates curl unzip ;;
    zypper) $SUDO zypper --non-interactive refresh; $SUDO zypper --non-interactive install git ca-certificates curl unzip ;;
    brew)   brew update; brew install git ;;
    *)      err "패키지 매니저를 인식하지 못했습니다. Git 수동 설치 필요."; exit 1 ;;
  esac
  ok "git 설치 완료: $(git --version)"
}

### ===== Python 보장 (venv 포함) =====
ensure_python() {
  if command -v python3 >/dev/null 2>&1; then
    ok "python3: $(python3 --version)"
  else
    local pm; pm="$(detect_pm)"; check_net || true
    case "$pm" in
      apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y python3 python3-venv python3-pip ;;
      dnf|yum)$SUDO "${pm}" install -y python3 python3-pip ;;  # venv 내장
      pacman) $SUDO pacman -Sy --noconfirm python python-pip ;;
      zypper) $SUDO zypper --non-interactive install python3 python3-pip python3-venv || $SUDO zypper --non-interactive install python311 python311-pip ;;
      brew)   brew update; brew install python ;;
      *)      err "Python 설치 불가한 환경입니다. 수동 설치 필요."; exit 1 ;;
    esac
    ok "python3 설치 완료: $(python3 --version)"
  fi
}

### ===== AWS CLI 보장 & 구성 =====
install_awscli() {
  check_net || true
  local os="$(uname -s)" arch="$(uname -m)"
  if [ "$os" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    log "Homebrew로 AWS CLI 설치"
    brew update
    brew install awscli
    return
  fi

  # 기본은 공식 v2 설치 스크립트 사용 (Linux)
  local url=""
  case "$arch" in
    x86_64|amd64) url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
    aarch64|arm64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
    *)
      warn "알 수 없는 아키텍처(${arch}) → 패키지 매니저로 시도"
      local pm; pm="$(detect_pm)"
      case "$pm" in
        apt)    $SUDO apt-get update -y; $SUDO apt-get install -y awscli ;; # (버전이 낮을 수 있음)
        dnf|yum)$SUDO "$pm" install -y awscli ;;
        pacman) $SUDO pacman -Sy --noconfirm aws-cli ;;
        zypper) $SUDO zypper --non-interactive install aws-cli ;;
        *)      err "AWS CLI 설치 방법을 결정하지 못했습니다."; exit 1 ;;
      esac
      return
      ;;
  esac

  log "AWS CLI v2 설치 (공식 패키지)"
  tmpd="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmpd/awscliv2.zip"
  unzip -q "$tmpd/awscliv2.zip" -d "$tmpd"
  if [ -n "$SUDO" ]; then
    $SUDO "$tmpd/aws/install" --update
  else
    # 사용자 경로 설치
    mkdir -p "$HOME/.local/aws-cli"
    "$tmpd/aws/install" -i "$HOME/.local/aws-cli" -b "$HOME/.local/bin" --update || {
      err "AWS CLI 사용자 설치 실패"; exit 1;
    }
    export PATH="$HOME/.local/bin:$PATH"
  fi
  rm -rf "$tmpd"
}

ensure_awscli() {
  if command -v aws >/dev/null 2>&1; then
    ok "aws: $(aws --version 2>&1 | head -n1)"
  else
    log "AWS CLI 미설치 — 설치 진행"
    install_awscli
    command -v aws >/dev/null 2>&1 || { err "AWS CLI 설치 실패"; exit 1; }
    ok "aws: $(aws --version 2>&1 | head -n1)"
  fi
}

configure_aws_if_needed() {
  local need_config="$FORCE_AWS_CONFIG"

  if [ "$need_config" = "0" ]; then
    if aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
      ok "AWS 자격증명 유효(프로파일: $AWS_PROFILE) — aws configure 생략"
      return 0
    fi
    warn "유효한 AWS 자격증명을 찾지 못했습니다(프로파일: $AWS_PROFILE). 설정을 진행합니다."
  else
    warn "FORCE_AWS_CONFIG=1 — aws configure를 다시 수행합니다."
  fi

  echo
  echo "=== aws configure (${AWS_PROFILE}) ==="
  read -rp "AWS Access Key ID: " AKID
  # Secret은 입력 숨김
  read -srp "AWS Secret Access Key: " SAK
  echo
  read -rp "Default region name [ap-northeast-2]: " REGION
  REGION="${REGION:-ap-northeast-2}"
  read -rp "Default output format [json]: " OUTF
  OUTF="${OUTF:-json}"
  # (선택) 세션 토큰
  read -rp "AWS Session Token (엔터로 생략): " STOK || true

  # 설정 반영 (history에 남지 않도록 aws configure set 사용)
  aws configure set aws_access_key_id "$AKID" --profile "$AWS_PROFILE"
  aws configure set aws_secret_access_key "$SAK" --profile "$AWS_PROFILE"
  [ -n "${STOK:-}" ] && aws configure set aws_session_token "$STOK" --profile "$AWS_PROFILE" || true
  aws configure set region "$REGION" --profile "$AWS_PROFILE"
  aws configure set output "$OUTF" --profile "$AWS_PROFILE"

  # 기본 프로파일 연결
  if [ "$AWS_PROFILE" != "default" ]; then
    aws configure set profile "$AWS_PROFILE" --profile default >/dev/null 2>&1 || true
  fi

  # 검증
  if aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    ok "AWS 자격증명 설정 완료(프로파일: $AWS_PROFILE)"
  else
    err "AWS 자격증명 검증 실패 — 키/권한/네트워크를 확인하세요."
    exit 1
  fi
}

### ===== Steampipe 보장 (권한/경로 자동 처리) =====
ensure_steampipe() {
  # 사용자/홈 경로 우선 추가
  export PATH="$HOME/.local/bin:$HOME/.steampipe/bin:$PATH"

  if command -v steampipe >/dev/null 2>&1; then
    ok "steampipe: $(steampipe -v | head -n1)"
  else
    check_net || true

    # 설치 대상 경로 결정
    dest="/usr/local/bin"
    if [ -n "$SUDO" ]; then
      log "Steampipe 설치 → ${dest} (sudo)"
      if curl -fsSL https://steampipe.io/install/steampipe.sh | $SUDO bash -s -- -b "$dest"; then
        :
      else
        warn "공식 스크립트 실패 → GitHub raw 스크립트로 재시도 (sudo)"
        curl -fsSL https://raw.githubusercontent.com/turbot/steampipe/main/scripts/install.sh | $SUDO bash -s -- -b "$dest" || {
          err "Steampipe 설치 실패"; exit 1;
        }
      fi
    else
      dest="$HOME/.local/bin"
      mkdir -p "$dest"
      log "Steampipe 설치 → ${dest} (사용자 영역)"
      if curl -fsSL https://steampipe.io/install/steampipe.sh | bash -s -- -b "$dest"; then
        :
      else
        warn "공식 스크립트 실패 → GitHub raw 스크립트로 재시도 (user)"
        curl -fsSL https://raw.githubusercontent.com/turbot/steampipe/main/scripts/install.sh | bash -s -- -b "$dest" || {
          err "Steampipe 설치 실패"; exit 1;
        }
      fi
    fi

    export PATH="$dest:$HOME/.local/bin:$HOME/.steampipe/bin:$PATH"
    command -v steampipe >/dev/null 2>&1 || { err "steampipe 명령어가 PATH에 없습니다 (${dest} 또는 ~/.steampipe/bin 확인)"; exit 1; }
    ok "steampipe 설치 완료: $(steampipe -v | head -n1)"
  fi

  # AWS 플러그인
  if steampipe plugin list 2>/dev/null | grep -q '^aws'; then
    ok "steampipe aws 플러그인 설치됨"
  else
    log "steampipe aws 플러그인 설치"
    steampipe plugin install aws
  fi

  # 서비스 시작
  if steampipe service status 2>/dev/null | grep -qi "running"; then
    ok "steampipe service 이미 실행 중"
  else
    log "steampipe service start"
    steampipe service start
    sleep 1
    steampipe service status >/dev/null 2>&1 || { err "steampipe service 기동 실패"; exit 1; }
    ok "steampipe service 실행"
  fi
}

### ===== 레포 클론/업데이트 =====
clone_or_update() {
  if [ -d "$TARGET_DIR/.git" ]; then
    log "기존 레포 → 업데이트"
    pushd "$TARGET_DIR" >/dev/null
    git fetch --all --prune
    git checkout "$BRANCH"
    git pull --ff-only origin "$BRANCH" || { warn "FF 불가 → rebase"; git pull --rebase origin "$BRANCH"; }
    popd >/dev/null
  else
    if [ -e "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR/.git" ]; then
      ts="$(date +%Y%m%d-%H%M%S)"; mv "$TARGET_DIR" "${TARGET_DIR}.bak-${ts}"; warn "동명 폴더 백업함"
    fi
    log "클론: $REPO_URL → $TARGET_DIR (브랜치: $BRANCH)"
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
  fi
  ok "레포 준비 완료: $TARGET_DIR"
}

### ===== API 백엔드 설치/실행 (uvicorn) =====
run_api_bg() {
  cd "$TARGET_DIR"
  mkdir -p logs

  # 기존 프로세스 처리
  if [ -f ".pid" ]; then
    old_pid="$(cat .pid || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
      if [ "$FORCE_RESTART" = "1" ]; then
        warn "기존 API 프로세스(${old_pid}) 종료"
        kill "$old_pid" || true
        sleep 1
      else
        ok "API 이미 실행 중 (PID=${old_pid})"; return 0
      fi
    fi
  fi

  # venv 생성/활성화
  if [ ! -d ".venv" ]; then
    log "Python venv 생성(.venv)"
    python3 -m venv .venv
  fi
  # shellcheck disable=SC1091
  . ".venv/bin/activate"

  python -m pip install --upgrade pip >/dev/null
  if [ -f "requirements.txt" ]; then
    log "requirements 설치"
    pip install -r requirements.txt
  else
    log "requirements.txt 없음 → 최소 패키지 설치"
    pip install fastapi uvicorn steampipe
  fi

  # 포트 점유 안내
  if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"${API_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
    warn "PORT ${API_PORT} 사용 중인 프로세스가 존재합니다."
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  logfile="logs/collector-api-${ts}.log"

  ok "Collector API 백그라운드 시작: HOST=${API_HOST} PORT=${API_PORT}"
  # uvicorn 백그라운드 실행
  HOST="${API_HOST}" PORT="${API_PORT}" nohup python -m uvicorn main:app --host "${API_HOST}" --port "${API_PORT}" --reload >"${logfile}" 2>&1 &

  pid="$!"
  echo "${pid}" > .pid
  ok "PID=${pid} (로그: ${logfile})"
  log "로그 보기: tail -f \"${logfile}\""
  log "중지: kill \$(cat .pid)"
}

### ===== 엔트리포인트 =====
main() {
  check_net || true
  ensure_git
  ensure_python
  ensure_awscli
  configure_aws_if_needed
  ensure_steampipe
  clone_or_update
  run_api_bg
}
main "$@"
