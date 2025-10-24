#!/usr/bin/env bash
# setup/set-front.sh — Git 확인 → SAGE-FRONT 클론/업데이트 → 의존성 설치 → html-webpack-plugin 문제 자동 패치 → 대시보드 백그라운드 실행
# 사용법:
#   bash setup/set-front.sh        # 기동
#   bash setup/set-front.sh stop   # 중지
#   bash setup/set-front.sh status # 상태
#   bash setup/set-front.sh logs   # 최근 로그 팔로우

set -euo pipefail

### ===== 설정 =====
REPO_URL="${REPO_URL:-https://github.com/BOB-DSPM/SAGE-FRONT.git}"
BRANCH="${BRANCH:-main}"
TARGET_DIR="${TARGET_DIR:-SAGE-FRONT}"
CLONE_DEPTH="${CLONE_DEPTH:-1}"

APP_SUBDIR="dspm_dashboard"
APP_HOST="${HOST:-0.0.0.0}"
APP_PORT="${PORT:-8200}"
NODE_LTS="${NODE_LTS:-lts/*}"
FORCE_RESTART="${FORCE_RESTART:-1}"

### ===== 출력 =====
log()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

### ===== 도구 =====
ensure_git() {
  if command -v git >/dev/null 2>&1; then
    ok "git: $(git --version)"
    return
  fi
  local pm
  pm="$( (command -v apt-get && echo apt) || (command -v dnf && echo dnf) || (command -v yum && echo yum) || (command -v pacman && echo pacman) || (command -v zypper && echo zypper) || (command -v brew && echo brew) || echo unknown )"
  case "$pm" in
    apt) sudo apt-get update -y && sudo apt-get install -y git ca-certificates curl ;;
    dnf|yum) sudo "$pm" install -y git ca-certificates curl ;;
    pacman) sudo pacman -Sy --noconfirm git ca-certificates curl ;;
    zypper) sudo zypper --non-interactive refresh && sudo zypper --non-interactive install git ca-certificates curl ;;
    brew) brew update && brew install git ;;
    *) err "git 미설치 & 자동설치 불가"; exit 1 ;;
  esac
  ok "git 설치 완료"
}

ensure_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    local major; major="$(node -v | sed 's/^v//;s/\..*$//')"
    if [ "${major:-0}" -ge 18 ]; then ok "Node: $(node -v), npm: $(npm -v)"; return; fi
  fi
  # nvm 설치
  if [ ! -d "$HOME/.nvm" ]; then
    log "nvm 설치"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  # shellcheck disable=SC1090
  . "$HOME/.nvm/nvm.sh"
  log "Node(${NODE_LTS}) 설치"
  nvm install "${NODE_LTS}"
  nvm alias default "${NODE_LTS}"
  nvm use default
  ok "Node: $(node -v), npm: $(npm -v)"
  npm config set fund false >/dev/null 2>&1 || true
  npm config set audit false >/dev/null 2>&1 || true
}

clone_or_update() {
  if [ -d "$TARGET_DIR/.git" ]; then
    log "기존 레포 감지 → 업데이트"
    git -C "$TARGET_DIR" fetch --all --prune
    git -C "$TARGET_DIR" checkout "$BRANCH"
    git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH" || git -C "$TARGET_DIR" pull --rebase origin "$BRANCH"
  else
    [ -e "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR/.git" ] && mv "$TARGET_DIR" "${TARGET_DIR}.bak-$(date +%Y%m%d-%H%M%S)"
    if [ -n "${CLONE_DEPTH}" ] && [ "${CLONE_DEPTH}" != "0" ]; then
      git clone --branch "$BRANCH" --depth "$CLONE_DEPTH" "$REPO_URL" "$TARGET_DIR"
    else
      git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
    fi
  fi
  ok "레포 준비 완료: $TARGET_DIR"
  [ -f "$TARGET_DIR/.gitmodules" ] && git -C "$TARGET_DIR" submodule update --init --recursive || true
}

install_deps() {
  cd "$TARGET_DIR/$APP_SUBDIR"
  mkdir -p logs

  # 깨끗한 설치 권장
  rm -rf node_modules
  if [ -f package-lock.json ]; then
    log "npm ci"
    npm ci
  else
    log "npm install"
    npm install
  fi

  # html-webpack-plugin 자동 패치(오류 케이스 대응)
  if ! npm ls html-webpack-plugin >/dev/null 2>&1; then
    npm i -D html-webpack-plugin@^5 webpack@^5 webpack-cli@^5
  fi
  if grep -R "html-webpack-plugin/lib/loader" -n . >/dev/null 2>&1; then
    log "구식 html-webpack-plugin 로더 경로 제거 패치"
    for f in $(grep -RIl "html-webpack-plugin/lib/loader" .); do
      cp "$f" "$f.bak"
      sed -i 's@.*html-webpack-plugin/lib/loader\.js!@@g' "$f"
    done
  fi
}

kill_if_running() {
  cd "$TARGET_DIR/$APP_SUBDIR"
  if [ -f ".pid" ]; then
    local pid; pid="$(cat .pid || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      if [ "$FORCE_RESTART" = "1" ]; then
        warn "기존 프로세스 종료(PID=${pid})"
        kill "$pid" || true
        sleep 1
      else
        ok "이미 실행 중(PID=${pid})"; return 1
      fi
    fi
  fi
  return 0
}

start_bg() {
  cd "$TARGET_DIR/$APP_SUBDIR"

  # 실행 스크립트 자동 선택
  local run_cmd="npm start"
  if grep -q '"dev":' package.json; then
    run_cmd="npm run dev"
  elif grep -q '"serve":' package.json; then
    run_cmd="npm run serve"
  fi

  # 포트 안내
  if command -v lsof >/dev/null 2>&1 && lsof -iTCP:"${APP_PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
    warn "PORT ${APP_PORT} 사용 중 프로세스 존재(무시하고 진행)"
  fi

  local ts logfile
  ts="$(date +%Y%m%d-%H%M%S)"
  logfile="logs/dashboard-${ts}.log"

  ok "프론트 시작: HOST=${APP_HOST} PORT=${APP_PORT} CMD='${run_cmd}'"
  HOST="${APP_HOST}" PORT="${APP_PORT}" nohup ${run_cmd} > "${logfile}" 2>&1 &
  echo "$!" > .pid
  ok "PID=$(cat .pid) (로그: ${logfile})"
  log "중지: kill \$(cat .pid)"
}

stop_front() {
  cd "$TARGET_DIR/$APP_SUBDIR" 2>/dev/null || { warn "디렉터리 없음: $TARGET_DIR/$APP_SUBDIR"; return 0; }
  if [ -f ".pid" ]; then
    local pid; pid="$(cat .pid)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      log "프로세스 종료(PID=${pid})"
      kill "$pid" || true
      sleep 1
      rm -f .pid
      ok "중지 완료"
      return 0
    fi
  fi
  warn "실행 중인 프로세스가 없습니다."
}

status_front() {
  cd "$TARGET_DIR/$APP_SUBDIR" 2>/dev/null || { warn "디렉터리 없음: $TARGET_DIR/$APP_SUBDIR"; return 0; }
  if [ -f ".pid" ]; then
    local pid; pid="$(cat .pid)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      ok "실행 중(PID=${pid}) — http://${APP_HOST}:${APP_PORT}"
      return 0
    fi
  fi
  warn "중지됨"
}

logs_follow() {
  cd "$TARGET_DIR/$APP_SUBDIR" 2>/dev/null || { warn "디렉터리 없음: $TARGET_DIR/$APP_SUBDIR"; return 0; }
  local lastlog
  lastlog="$(ls -1t logs/dashboard-*.log 2>/dev/null | head -n1 || true)"
  if [ -n "${lastlog:-}" ] && [ -f "$lastlog" ]; then
    log "로그 팔로우: $lastlog (Ctrl+C 종료)"
    tail -n 200 -f "$lastlog"
  else
    warn "로그 파일이 없습니다."
  fi
}

### ===== 엔트리 =====
cmd="${1:-run}"
case "$cmd" in
  run|"")
    ensure_git
    ensure_node
    clone_or_update
    install_deps
    if kill_if_running; then start_bg; fi
    ;;
  stop)     stop_front ;;
  restart)  stop_front || true; ensure_git; ensure_node; clone_or_update; install_deps; start_bg ;;
  status)   status_front ;;
  logs)     logs_follow ;;
  *)
    echo "Usage: $0 {run|stop|restart|status|logs}"
    exit 1
    ;;
esac
