#!/usr/bin/env bash
# set-front.sh — Git 확인/설치 → SAGE-FRONT 클론/업데이트 → dspm_dashboard 백그라운드 실행/관리
# 사용법:
#   bash set-front.sh start     # 설치/업데이트 후 백그라운드 실행
#   bash set-front.sh stop      # 백그라운드 중지
#   bash set-front.sh restart   # 중지 후 재시작
#   bash set-front.sh status    # 상태 확인
#   bash set-front.sh logs      # 최근 로그 tail
#
# 환경변수(선택):
#   REPO_URL=https://github.com/BOB-DSPM/SAGE-FRONT.git
#   BRANCH=main
#   TARGET_DIR=SAGE-FRONT
#   CLONE_DEPTH=1
#   APP_SUBDIR=dspm_dashboard
#   HOST=0.0.0.0
#   PORT=8200
#   NODE_LTS=lts/*           # 특정 버전 고정 시 20/22 등
#   FORCE_RESTART=0          # 1이면 기존 프로세스 종료 후 재시작
#   RUN_CMD="npm start"      # 필요 시 커스텀 실행 커맨드

set -Eeuo pipefail

### =============== 설정 ===============
REPO_URL="${REPO_URL:-https://github.com/BOB-DSPM/SAGE-FRONT.git}"
BRANCH="${BRANCH:-main}"
TARGET_DIR="${TARGET_DIR:-SAGE-FRONT}"
CLONE_DEPTH="${CLONE_DEPTH:-1}"

APP_SUBDIR="${APP_SUBDIR:-dspm_dashboard}"
APP_HOST="${HOST:-0.0.0.0}"
APP_PORT="${PORT:-8200}"
NODE_LTS="${NODE_LTS:-lts/*}"
FORCE_RESTART="${FORCE_RESTART:-0}"
RUN_CMD="${RUN_CMD:-npm start}"

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
  if command -v pacman   >/dev/null 2>&1; then echo "pacman"; return; fi  if command -v zypper   >/dev/null 2>&1; then echo "zypper"; return; fi
  if command -v brew     >/dev/null 2>&1; then echo "brew"; return; fi
  if command -v choco    >/dev/null 2>&1; then echo "choco"; return; fi
  echo "unknown"
}

install_pkg() {
  local pm="$1"; shift
  case "$pm" in
    apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "$@";;
    dnf)    $SUDO dnf install -y "$@";;
    yum)    $SUDO yum install -y "$@";;
    pacman) $SUDO pacman -Sy --noconfirm "$@";;
    zypper) $SUDO zypper --non-interactive refresh; $SUDO zypper --non-interactive install "$@";;
    brew)   brew update; brew install "$@";;
    choco)  choco install -y "$@";;
    *)      return 1;;
  esac
}

ensure_basic_tools() {
  local pm; pm="$(detect_pm)"
  case "$pm" in
    apt)    install_pkg apt ca-certificates curl git lsof netcat-openbsd >/dev/null 2>&1 || true ;;
    dnf|yum)install_pkg "$pm" ca-certificates curl git lsof nmap-ncat     >/dev/null 2>&1 || true ;;
    pacman) install_pkg pacman ca-certificates curl git lsof ncat        >/dev/null 2>&1 || true ;;
    zypper) install_pkg zypper ca-certificates curl git lsof nmap        >/dev/null 2>&1 || true ;;
    brew)   install_pkg brew ca-certificates curl git lsof nmap          >/dev/null 2>&1 || true ;;
    choco)  install_pkg choco git curl nmap                              >/dev/null 2>&1 || true ;;
  esac
  command -v git  >/dev/null 2>&1 || { err "git 설치 실패"; exit 1; }
  command -v curl >/dev/null 2>&1 || { err "curl 설치 실패"; exit 1; }
}

ensure_git() {
  ensure_basic_tools
  ok "git: $(git --version)"
  git config --global http.version HTTP/1.1 || true
}

install_nvm_and_node() {
  if [ ! -d "${HOME}/.nvm" ]; then
    log "nvm 설치"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  # shellcheck disable=SC1090
  . "${HOME}/.nvm/nvm.sh"
  log "Node.js(${NODE_LTS}) 설치/사용"
  nvm install "${NODE_LTS}"
  nvm alias default "${NODE_LTS}"
  nvm use default
  ok "node: $(node -v), npm: $(npm -v)"
}

ensure_node() {
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    warn "Node.js/npm 미설치 — nvm 경유 설치 진행"
    install_nvm_and_node
  fi
  local major; major="$(node -v | sed 's/^v//;s/\..*$//')"
  if [ "${major:-0}" -lt 18 ]; then
    warn "Node 버전이 낮음($(node -v)) → 최신 LTS로 업데이트"
    install_nvm_and_node
  fi
  npm config set fund false >/dev/null 2>&1 || true
  npm config set audit false >/dev/null 2>&1 || true
}

clone_or_update() {
  if [ -d "$TARGET_DIR/.git" ]; then
    log "기존 레포 감지: $TARGET_DIR → 동기화"
    pushd "$TARGET_DIR" >/dev/null
    local current_url; current_url="$(git config --get remote.origin.url || true)"
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
      local ts bak; ts="$(date +%Y%m%d-%H%M%S)"; bak="${TARGET_DIR}.bak-${ts}"
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

### 절대 경로 유틸
app_dir() { (cd "${TARGET_DIR}/${APP_SUBDIR}" 2>/dev/null && pwd) || printf "%s" "${TARGET_DIR}/${APP_SUBDIR}"; }
pid_file() { printf "%s/.pid" "$(app_dir)"; }
log_dir()  { printf "%s/logs" "$(app_dir)"; }

### Webpack 레거시 패치
patch_webpack_legacy() {
  local dir="$1"
  pushd "$dir" >/dev/null

  # 1) html-webpack-plugin 로더 경로 하드코딩 제거
  if grep -R "html-webpack-plugin/lib/loader\.js" -n . >/dev/null 2>&1; then
    warn "레거시 html-webpack-plugin 로더 경로 패치"
    sed -i -E 's@!?html-webpack-plugin/lib/loader\.js!?@@g' webpack*.js 2>/dev/null || true
    sed -i -E 's@!?html-webpack-plugin/lib/loader\.js!?@@g' config/webpack*.js 2>/dev/null || true
    sed -i -E "s@require\.resolve\(['\"][^)]*html-webpack-plugin/lib/loader\.js['\"]\)!!@@g" webpack*.js config/webpack*.js 2>/dev/null || true
  fi

  # 2) 플러그인/웹팩 보강 설치
  if ! node -e "require('html-webpack-plugin')" >/dev/null 2>&1; then
    npm i -D html-webpack-plugin@^5 --no-fund --no-audit || true
  fi
  if ! node -e "require('webpack')" >/dev/null 2>&1; then
    npm i -D webpack webpack-cli --no-fund --no-audit || true
  fi

  # 3) 템플릿 위치 보정
  if [ ! -f "public/index.html" ]; then
    mkdir -p public
    if [ -f "src/index.html" ]; then
      cp -n src/index.html public/index.html
    elif [ -f "index.html" ]; then
      cp -n index.html public/index.html
    else
      cat > public/index.html <<'EOF'
<!doctype html><html><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>SAGE Front</title></head><body><div id="root"></div></body></html>
EOF
    fi
  fi

  popd >/dev/null
}

ensure_app_deps() {
  local app_dir_abs="$1"
  pushd "$app_dir_abs" >/dev/null

  # 잠재 빌드 오류 보강
  if [ -d "node_modules" ]; then
    if [ ! -d "node_modules/html-webpack-plugin" ] || [ ! -d "node_modules/webpack" ]; then
      warn "webpack/html-webpack-plugin 보강 설치"
      npm i -D webpack webpack-cli html-webpack-plugin@^5 --no-fund --no-audit || true
    fi
  fi

  # 패키지 설치: lock 우선
  if [ -f "pnpm-lock.yaml" ]; then
    command -v pnpm >/dev/null 2>&1 || npm i -g pnpm >/dev/null 2>&1 || true
    log "pnpm i"
    pnpm i
  elif [ -f "yarn.lock" ]; then
    command -v yarn >/dev/null 2>&1 || npm i -g yarn >/dev/null 2>&1 || true
    log "yarn install --frozen-lockfile (fallback: yarn install)"
    yarn install --frozen-lockfile || yarn install
  elif [ -f "package-lock.json" ]; then
    log "npm ci"
    npm ci
  else
    log "npm install"
    npm install
  fi

  # 레거시 Webpack 설정 패치
  patch_webpack_legacy "$app_dir_abs"

  popd >/dev/null
}

### 네트워크/프로세스
is_listening() {
  local port="$1"
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$port" >/dev/null 2>&1
  elif command -v ncat >/dev/null 2>&1; then
    ncat -z 127.0.0.1 "$port" >/dev/null 2>&1
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
  else
    return 1
  fi
}

wait_until_up() {
  local port="$1" timeout="${2:-30}" i=0
  while [ "$i" -lt "$timeout" ]; do
    if is_listening "$port"; then return 0; fi
    sleep 1; i=$((i+1))
  done
  return 1
}

stop_if_running() {
  local pf; pf="$(pid_file)"
  if [ -f "$pf" ]; then
    local old_pid; old_pid="$(cat "$pf" 2>/dev/null || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
      log "기존 프로세스 종료(PID=$old_pid)"
      kill "$old_pid" || true
      sleep 1
      if kill -0 "$old_pid" >/dev/null 2>&1; then
        warn "강제 종료 시도"
        kill -9 "$old_pid" || true
      fi
    fi
    rm -f "$pf"
  fi
}

### 실행/중지/상태/로그
start_app() {
  ensure_git
  clone_or_update
  ensure_node

  local dir; dir="$(app_dir)"
  [ -d "$dir" ] || { err "앱 디렉터리 없음: ${dir}"; exit 1; }

  local abs_dir; abs_dir="$(cd "$dir" && pwd)"
  local abs_log_dir; abs_log_dir="${abs_dir}/logs"
  mkdir -p "$abs_log_dir"

  # 기존 실행 항목 정리
  if [ -f "$(pid_file)" ]; then
    local old_pid; old_pid="$(cat "$(pid_file)" 2>/dev/null || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
      if [ "$FORCE_RESTART" = "1" ]; then
        warn "기존 프로세스(${old_pid}) 종료 후 재시작(FORCE_RESTART=1)"
        stop_if_running
      else
        ok "이미 실행 중입니다. PID=${old_pid}"
        log "포트 ${APP_PORT} 점유 여부 확인 필요 → status / logs 참고"
        return 0
      fi
    fi
  fi

  ensure_app_deps "$abs_dir"

  local ts logfile
  ts="$(date +%Y%m%d-%H%M%S)"
  logfile="${abs_log_dir}/dashboard-${ts}.log"

  ok "대시보드 백그라운드 시작: HOST=${APP_HOST} PORT=${APP_PORT}"
  (
    cd "$abs_dir"
    HOST="${APP_HOST}" PORT="${APP_PORT}" nohup bash -lc "$RUN_CMD" >"${logfile}" 2>&1 &
    echo $! > .pid
  )

  local pid; pid="$(cat "$(pid_file)")"
  ok "PID=${pid} (로그: ${logfile})"
  if wait_until_up "${APP_PORT}" 30; then
    ok "포트 ${APP_PORT} 응답 확인"
  else
    warn "포트 ${APP_PORT} 응답 없음 — 빌드/의존성 로그 확인 필요"
    log "최근 로그 확인: tail -n 200 \"${logfile}\" || tail -n 200 \"${abs_dir}/nohup.out\""
  fi
}

stop_app() {
  local dir; dir="$(app_dir)"
  [ -d "$dir" ] || { warn "앱 디렉터리 없음: ${dir}"; return 0; }
  stop_if_running
  ok "중지 완료"
}

status_app() {
  local pf; pf="$(pid_file)"
  if [ -f "$pf" ]; then
    local pid; pid="$(cat "$pf" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      ok "실행 중(PID=$pid)"
    else
      warn "PID 파일은 있으나 프로세스 없음"
    fi
  else
    warn "실행 중 아님"
  fi
  if is_listening "$APP_PORT"; then
    ok "포트 ${APP_PORT} LISTEN 중"
  else
    warn "포트 ${APP_PORT} 비활성"
  fi
}

logs_app() {
  local dir; dir="$(app_dir)"
  [ -d "$dir" ] || { err "앱 디렉터리 없음: ${dir}"; exit 1; }
  local abs_dir; abs_dir="$(cd "$dir" && pwd)"
  local lastlog
  lastlog="$(ls -1t "${abs_dir}/logs"/dashboard-*.log 2>/dev/null | head -n1 || true)"
  if [ -n "$lastlog" ] && [ -f "$lastlog" ]; then
    log "tail -f $lastlog"
    tail -f "$lastlog"
  else
    warn "로그 파일이 없습니다. (대안) tail -f \"${abs_dir}/nohup.out\""
  fi
}

### 엔트리포인트
cmd="${1:-start}"
case "$cmd" in
  start)   start_app ;;
  stop)    stop_app ;;
  restart) stop_app; start_app ;;
  status)  status_app ;;
  logs)    logs_app ;;
  *)
    err "알 수 없는 명령: $cmd
사용법: $0 {start|stop|restart|status|logs}"
    exit 1
    ;;
esac
