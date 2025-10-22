#!/usr/bin/env bash
# setup.sh — Git 확인/설치 → SAGE-FRONT 클론/업데이트 → dspm_dashboard 백그라운드 실행
# 대상 OS: Ubuntu/Debian, RHEL/CentOS/Alma/Rocky, Amazon Linux, Fedora, Arch, openSUSE, macOS, Windows(WSL/Chocolatey)

set -euo pipefail

### =============== 설정 ===============
REPO_URL="${REPO_URL:-https://github.com/BOB-DSPM/SAGE-FRONT.git}"
BRANCH="${BRANCH:-main}"
TARGET_DIR="${TARGET_DIR:-SAGE-FRONT}"
CLONE_DEPTH="${CLONE_DEPTH:-1}"

APP_SUBDIR="dspm_dashboard"
APP_HOST="${HOST:-0.0.0.0}"
APP_PORT="${PORT:-8200}"
NODE_LTS="${NODE_LTS:-lts/*}"     # 특정 버전 고정 시 22 등의 숫자로 교체
FORCE_RESTART="${FORCE_RESTART:-0}" # 1이면 기존 프로세스 종료 후 재시작

### =============== 출력 도우미 ===============
log()   { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }
ok()    { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }

### =============== 권한/패키지 관리자 감지 ===============
SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else warn "root 아님 && sudo 없음"; fi
fi

detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  if command -v dnf      >/dev/null 2>&1; then echo "dnf"; return; fi
  if command -v yum      >/dev/null 2>&1; then echo "yum"; return; fi
  if command -v pacman   >/dev/null 2>&1; then echo "pacman"; return; fi
  if command -v zypper   >/dev/null 2>&1; then echo "zypper"; return; fi
  if command -v brew     >/dev/null 2>&1; then echo "brew"; return; fi
  if command -v choco    >/dev/null 2>&1; then echo "choco"; return; fi
  echo "unknown"
}

check_network() {
  if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 || curl -s --max-time 3 https://github.com >/dev/null 2>&1; then
    return 0
  fi
  warn "네트워크 연결이 불안정합니다. 설치/클론이 실패할 수 있습니다."
}

### =============== Git 설치 보장 ===============
install_git() {
  local pm; pm="$(detect_pm)"
  check_network || true
  case "$pm" in
    apt)    log "apt로 git 설치"; DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y git ca-certificates curl ;;
    dnf)    log "dnf로 git 설치"; $SUDO dnf install -y git ca-certificates curl ;;
    yum)    log "yum로 git 설치"; $SUDO yum install -y git ca-certificates curl ;;
    pacman) log "pacman으로 git 설치"; $SUDO pacman -Sy --noconfirm git ca-certificates curl ;;
    zypper) log "zypper로 git 설치"; $SUDO zypper --non-interactive refresh; $SUDO zypper --non-interactive install git ca-certificates curl ;;
    brew)   log "Homebrew로 git 설치"; brew update; brew install git ;;
    choco)  log "Chocolatey로 git 설치"; choco install git -y ;;
    *)      err "지원되지 않는 OS입니다. Git 수동 설치 필요: https://git-scm.com/downloads"; exit 1 ;;
  esac
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    ok "git 이미 설치됨: $(git --version)"
  else
    warn "git 미설치 — 설치를 시작합니다."
    install_git
    command -v git >/dev/null 2>&1 || { err "git 설치 실패"; exit 1; }
    ok "git 설치 완료: $(git --version)"
  fi
  git config --global http.version HTTP/1.1 || true
}

### =============== Node.js 설치 보장 (nvm 우선) ===============
install_nvm_and_node() {
  check_network || true
  if [ ! -d "${HOME}/.nvm" ]; then
    log "nvm 설치"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  # shellcheck disable=SC1090
  . "${HOME}/.nvm/nvm.sh"
  log "Node.js(${NODE_LTS}) 설치"
  nvm install "${NODE_LTS}"
  nvm alias default "${NODE_LTS}"
  nvm use default
  ok "node: $(node -v), npm: $(npm -v)"
}

ensure_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    major="$(node -v | sed 's/^v//;s/\..*$//')"
    if [ "${major:-0}" -lt 18 ]; then
      warn "Node 버전이 낮음($(node -v)) → 최신 LTS로 업데이트"
      install_nvm_and_node
    else
      ok "Node 존재: $(node -v), npm: $(npm -v)"
    fi
  else
    warn "Node.js/npm 미설치 — nvm 경유 설치 진행"
    install_nvm_and_node
  fi
  npm config set fund false >/dev/null 2>&1 || true
  npm config set audit false >/dev/null 2>&1 || true
}

### =============== 레포 클론/업데이트 ===============
clone_or_update() {
  if [ -d "$TARGET_DIR/.git" ]; then
    log "기존 레포 감지: $TARGET_DIR → 동기화"
    pushd "$TARGET_DIR" >/dev/null
    current_url="$(git config --get remote.origin.url || true)"
    if [ "$current_url" != "$REPO_URL" ]; then
      warn "원격 변경: $current_url → $REPO_URL"; git remote set-url origin "$REPO_URL"
    fi
    git fetch --all --prune
    git checkout "$BRANCH"
    git pull --ff-only origin "$BRANCH" || { warn "fast-forward 불가 → rebase"; git pull --rebase origin "$BRANCH"; }
    popd >/dev/null
    ok "레포 업데이트 완료"
  else
    if [ -e "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR/.git" ]; then
      ts="$(date +%Y%m%d-%H%M%S)"; bak="${TARGET_DIR}.bak-${ts}"
      warn "동명 디렉터리(깃 아님) → 백업: $bak"; mv "$TARGET_DIR" "$bak"
    fi
    if [ -n "${CLONE_DEPTH}" ] && [ "${CLONE_DEPTH}" != "0" ]; then
      log "얕은 클론(depth=${CLONE_DEPTH}) → $TARGET_DIR (브랜치: $BRANCH)"
      git clone --branch "$BRANCH" --depth "$CLONE_DEPTH" "$REPO_URL" "$TARGET_DIR"
    else
      log "전체 이력 클론 → $TARGET_DIR (브랜치: $BRANCH)"
      git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
    fi
    ok "클론 완료"
  fi
  if [ -f "$TARGET_DIR/.gitmodules" ]; then
    log "서브모듈 초기화"; git -C "$TARGET_DIR" submodule update --init --recursive
  fi
}

### =============== 앱 설치/백그라운드 실행 ===============
run_dashboard_bg() {
  local app_dir="${TARGET_DIR}/${APP_SUBDIR}"
  [ -d "$app_dir" ] || { err "앱 디렉터리 없음: ${app_dir}"; exit 1; }

  cd "$app_dir"
  mkdir -p logs

  # 이미 실행 중인지 확인
  if [ -f ".pid" ]; then
    old_pid="$(cat .pid || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
      if [ "$FORCE_RESTART" = "1" ]; then
        warn "기존 프로세스(${old_pid}) 종료 후 재시작(FORCE_RESTART=1)"
        kill "$old_pid" || true
        sleep 1
      else
        ok "이미 실행 중입니다. PID=${old_pid}"
        log "포트 ${APP_PORT} 점유 여부를 확인하세요."
        return 0
      fi
    fi
  fi

  # 의존성 설치
  if [ -f package-lock.json ]; then
    log "npm ci 실행"; npm ci
  else
    log "npm install 실행"; npm install
  fi

  # 포트 사용 여부 안내
  if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"${APP_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
    warn "PORT ${APP_PORT} 사용 중인 프로세스가 있습니다."
  fi

  # 로그 파일명
  ts="$(date +%Y%m%d-%H%M%S)"
  logfile="logs/dashboard-${ts}.log"

  ok "대시보드 백그라운드 시작: HOST=${APP_HOST} PORT=${APP_PORT}"
  # 백그라운드 실행 (&) + nohup로 터미널 분리, 로그 파일 저장
  HOST="${APP_HOST}" PORT="${APP_PORT}" nohup npm start >"${logfile}" 2>&1 &

  pid="$!"
  echo "${pid}" > .pid

  ok "PID=${pid} (로그: ${logfile})"
  log "최근 로그 확인: tail -f \"${logfile}\""
  log "중지: kill \$(cat .pid)"
}

### =============== 엔트리포인트 ===============
main() {
  ensure_git
  clone_or_update
  ensure_node
  run_dashboard_bg
}

main "$@"
