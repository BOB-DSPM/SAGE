#!/usr/bin/env bash
# setup-compliance-show.sh
# DSPM_Compliance-show: 클론 → .venv 구성 → requirements 설치 → CSV 적재 → API(Uvicorn) 백그라운드 실행
# 사용법:
#   bash setup-compliance-show.sh start   # 처음 실행(또는 재실행)
#   bash setup-compliance-show.sh stop    # 백그라운드 서버 중지
#   bash setup-compliance-show.sh restart # 중지 후 재실행
#   bash setup-compliance-show.sh status  # 상태 확인
#   bash setup-compliance-show.sh logs    # 최근 로그 보기(팔로우)
#
# 환경변수(필요 시 덮어쓰기):
#   REPO_URL="https://github.com/BOB-DSPM/DSPM_Compliance-show.git"
#   BRANCH="main"
#   TARGET_DIR="DSPM_Compliance-show"
#   API_HOST="0.0.0.0"
#   API_PORT="8003"
#   REQUIREMENTS_CSV="../compliance-gorn.csv"
#   MAPPINGS_CSV="../mapping-standard.csv"
#   SKIP_CSV_LOAD="0"            # 1로 설정 시 CSV 적재 생략
#   FORCE_RESTART="1"            # 1이면 기존 PID 종료 후 재시작
#   USE_PYTHON_MODULE_RUN="0"    # 1이면 `python -m app.main`으로 실행(포트 고정 코드라면 권장)

set -euo pipefail

### ===== 기본 설정 =====
REPO_URL="${REPO_URL:-https://github.com/BOB-DSPM/DSPM_Compliance-show.git}"
BRANCH="${BRANCH:-main}"
TARGET_DIR="${TARGET_DIR:-DSPM_Compliance-show}"

API_HOST="${API_HOST:-0.0.0.0}"
API_PORT="${API_PORT:-8003}"

REQUIREMENTS_CSV="${REQUIREMENTS_CSV:-../compliance-gorn.csv}"
MAPPINGS_CSV="${MAPPINGS_CSV:-../mapping-standard.csv}"

SKIP_CSV_LOAD="${SKIP_CSV_LOAD:-0}"
FORCE_RESTART="${FORCE_RESTART:-1}"
USE_PYTHON_MODULE_RUN="${USE_PYTHON_MODULE_RUN:-0}"

LOG_DIR="logs"
PID_FILE=".pid"

### ===== 출력 헬퍼 =====
log()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

### ===== sudo / 패키지 관리자 판별 =====
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

### ===== 네트워크 체크(선택) =====
check_net() {
  if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 || curl -fsS --max-time 3 https://github.com >/dev/null 2>&1; then
    return 0
  fi
  warn "네트워크가 불안정합니다. 클론/설치가 실패할 수 있습니다."
}

### ===== 필수 패키지: git, curl, lsof =====
ensure_base_pkgs() {
  local pm need=()
  pm="$(detect_pm)"
  command -v git  >/dev/null 2>&1 || need+=("git")
  command -v curl >/dev/null 2>&1 || need+=("curl")
  command -v lsof >/dev/null 2>&1 || need+=("lsof")
  [ "${#need[@]}" -eq 0 ] && { ok "필수 패키지 이미 설치됨"; return; }
  log "필수 패키지 설치: ${need[*]}"
  case "$pm" in
    apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "${need[@]}";;
    dnf|yum)$SUDO "$pm" install -y "${need[@]}";;
    pacman) $SUDO pacman -Sy --noconfirm "${need[@]}";;
    zypper) $SUDO zypper --non-interactive refresh; $SUDO zypper --non-interactive install "${need[@]}";;
    brew)   for p in "${need[@]}"; do brew list --versions "$p" >/dev/null 2>&1 || brew install "$p"; done;;
    *)      warn "패키지 매니저를 인식하지 못했습니다. 수동으로 git/curl/lsof 설치가 필요할 수 있습니다.";;
  esac
}

### ===== Python(venv/pip 포함) 보장 =====
ensure_python() {
  if command -v python3 >/dev/null 2>&1; then
    ok "python3: $(python3 --version)"
  else
    local pm; pm="$(detect_pm)"; check_net || true
    case "$pm" in
      apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y python3 python3-pip ;;
      dnf|yum)$SUDO "$pm" install -y python3 python3-pip ;;
      pacman) $SUDO pacman -Sy --noconfirm python python-pip ;;
      zypper) $SUDO zypper --non-interactive install python3 python3-pip || $SUDO zypper --non-interactive install python311 python311-pip ;;
      brew)   brew update; brew install python ;;
      *)      err "Python 설치 불가한 환경입니다. 수동 설치 필요."; exit 1 ;;
    esac
    ok "python3 설치 완료: $(python3 --version)"
  fi
}

ensure_python_venv_ready() {
  # ensurepip/venv 확인
  if python3 -m ensurepip --version >/dev/null 2>&1 && python3 -c "import venv" >/dev/null 2>&1; then
    ok "Python venv/ensurepip 사용 가능"
    return
  fi
  warn "Python venv/ensurepip 미탑재 → 설치 시도"
  local pm; pm="$(detect_pm)"
  case "$pm" in
    apt)
      PYMINOR="$(python3 -c 'import sys;print(f\"{sys.version_info.major}.{sys.version_info.minor}\")' 2>/dev/null || echo 3.12)"
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y
      $SUDO apt-get install -y "python${PYMINOR}-venv" python3-pip || $SUDO apt-get install -y python3-venv python3-pip
      ;;
    dnf|yum) $SUDO "$pm" install -y python3 python3-pip || true ;;
    pacman)  $SUDO pacman -Sy --noconfirm python python-pip || true ;;
    zypper)  $SUDO zypper --non-interactive install python3-venv python3-pip || $SUDO zypper --non-interactive install python311-venv python311-pip || true ;;
    brew)    brew update; brew install python || true ;;
    *)       warn "패키지 매니저 인식 실패 — virtualenv 대체 경로 사용" ;;
  esac

  if python3 -m ensurepip --version >/dev/null 2>&1 && python3 -c "import venv" >/dev/null 2>&1; then
    ok "Python venv/ensurepip 준비 완료"
    return
  fi

  warn "venv 여전히 불가 → virtualenv로 대체"
  python3 -m ensurepip --default-pip >/dev/null 2>&1 || true
  python3 -m pip install --user --upgrade pip virtualenv
  export PATH="$HOME/.local/bin:$PATH"
  command -v virtualenv >/dev/null 2>&1 || { err "virtualenv 설치 실패"; exit 1; }
  ok "virtualenv 사용 가능"
}

### ===== 레포 클론/업데이트 =====
clone_or_update() {
  if [ -d "$TARGET_DIR/.git" ]; then
    log "기존 레포 업데이트"
    git -C "$TARGET_DIR" fetch --all --prune
    git -C "$TARGET_DIR" checkout "$BRANCH"
    git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH" || git -C "$TARGET_DIR" pull --rebase origin "$BRANCH"
  else
    if [ -e "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR/.git" ]; then
      ts="$(date +%Y%m%d-%H%M%S)"; mv "$TARGET_DIR" "${TARGET_DIR}.bak-${ts}"; warn "동명 폴더 백업: ${TARGET_DIR}.bak-${ts}"
    fi
    log "클론: $REPO_URL → $TARGET_DIR (브랜치: $BRANCH)"
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
  fi
  ok "레포 준비 완료: $TARGET_DIR"
}

### ===== 포트 사용 중이면 종료(옵션) =====
kill_port_if_needed() {
  if lsof -iTCP:"$API_PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
    local pids; pids="$(lsof -iTCP:"$API_PORT" -sTCP:LISTEN -t | tr '\n' ' ')"
    if [ "${FORCE_RESTART:-1}" = "1" ]; then
      warn "포트 ${API_PORT} 사용 중 프로세스 종료: ${pids}"
      kill $pids || true
      sleep 1
    else
      err "포트 ${API_PORT}가 이미 사용 중입니다. FORCE_RESTART=1 로 재시도하세요."
      exit 1
    fi
  fi
}

### ===== venv 생성/활성화 & 의존성 설치 =====
prepare_venv_and_deps() {
  cd "$TARGET_DIR"
  mkdir -p "$LOG_DIR"

  if [ ! -d ".venv" ]; then
    log "Python 가상환경 생성(.venv)"
    if command -v virtualenv >/dev/null 2>&1; then
      python3 -m virtualenv .venv
    else
      python3 -m venv .venv
    fi
  fi
  # shellcheck disable=SC1091
  . ".venv/bin/activate"

  python -m pip install --upgrade pip
  if [ -f "requirements.txt" ]; then
    log "requirements 설치"
    pip install -r requirements.txt
  else
    warn "requirements.txt 없음 → 최소 패키지 설치(fastapi, uvicorn, pydantic 등)"
    pip install fastapi uvicorn "pydantic>=2" "sqlalchemy>=2" "python-dotenv"
  fi
  ok "가상환경 및 의존성 준비 완료"
}

### ===== CSV 적재 =====
load_csv() {
  if [ "${SKIP_CSV_LOAD}" = "1" ]; then
    warn "CSV 적재 건너뜀(SKIP_CSV_LOAD=1)"
    return 0
  fi
  if [ ! -f "$REQUIREMENTS_CSV" ] || [ ! -f "$MAPPINGS_CSV" ]; then
    warn "CSV 경로 확인 필요: REQUIREMENTS_CSV='${REQUIREMENTS_CSV}', MAPPINGS_CSV='${MAPPINGS_CSV}'"
  fi
  log "CSV 적재 시작"
  python -m scripts.load_csv --requirements "${REQUIREMENTS_CSV}" --mappings "${MAPPINGS_CSV}"
  ok "✅ CSV 적재 완료"
}

### ===== API 백그라운드 실행 =====
start_api_bg() {
  kill_port_if_needed

  # 기존 PID 정리
  if [ -f "$PID_FILE" ]; then
    local old_pid; old_pid="$(cat "$PID_FILE" || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
      if [ "${FORCE_RESTART:-1}" = "1" ]; then
        warn "기존 프로세스 종료(PID=${old_pid})"
        kill "$old_pid" || true
        sleep 1
      else
        ok "이미 실행 중(PID=${old_pid})"
        return 0
      fi
    fi
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  logfile="${LOG_DIR}/compliance-show-${ts}.log"

  ok "API 백그라운드 시작: ${API_HOST}:${API_PORT}"
  if [ "${USE_PYTHON_MODULE_RUN}" = "1" ]; then
    # 리포의 app.main 내부에서 uvicorn 실행(README 방식)
    APP_HOST="${API_HOST}" APP_PORT="${API_PORT}" \
      nohup python -m app.main > "${logfile}" 2>&1 &
  else
    # uvicorn 직접 호출(포트/호스트 고정하고 싶을 때)
    nohup python -m uvicorn app.main:app \
      --host "${API_HOST}" \
      --port "${API_PORT}" \
      --log-level info \
      > "${logfile}" 2>&1 &
  fi

  echo "$!" > "$PID_FILE"
  ok "PID=$(cat "$PID_FILE") (로그: ${logfile})"
  log "상태 확인: curl -s http://${API_HOST}:${API_PORT}/health"
  log "문서:       http://localhost:${API_PORT}/docs"
}

### ===== 중지/상태/로그 =====
stop_api() {
  cd "$TARGET_DIR" 2>/dev/null || { warn "디렉터리 없음: $TARGET_DIR"; return 0; }
  if [ -f "$PID_FILE" ]; then
    local pid; pid="$(cat "$PID_FILE")"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      log "프로세스 종료(PID=${pid})"
      kill "$pid" || true
      sleep 1
      rm -f "$PID_FILE"
      ok "중지 완료"
      return 0
    fi
  fi
  warn "실행 중인 프로세스가 없습니다."
}

status_api() {
  cd "$TARGET_DIR" 2>/dev/null || { warn "디렉터리 없음: $TARGET_DIR"; return 0; }
  if [ -f "$PID_FILE" ]; then
    local pid; pid="$(cat "$PID_FILE")"
    if [ -n "${pid:-}" ] && kill -0 "$pid" >/dev/null 2>&1; then
      ok "실행 중(PID=${pid}) — http://${API_HOST}:${API_PORT}"
      return 0
    fi
  fi
  warn "중지됨"
}

logs_follow() {
  cd "$TARGET_DIR" 2>/dev/null || { warn "디렉터리 없음: $TARGET_DIR"; return 0; }
  local lastlog
  lastlog="$(ls -1t ${LOG_DIR}/compliance-show-*.log 2>/dev/null | head -n1 || true)"
  if [ -n "${lastlog:-}" ] && [ -f "$lastlog" ]; then
    log "로그 팔로우: $lastlog (중지: Ctrl+C)"
    tail -n 200 -f "$lastlog"
  else
    warn "로그 파일이 없습니다."
  fi
}

### ===== 엔트리 =====
cmd="${1:-start}"
case "$cmd" in
  start)
    check_net || true
    ensure_base_pkgs
    ensure_python
    ensure_python_venv_ready
    clone_or_update
    prepare_venv_and_deps
    load_csv
    start_api_bg
    ;;
  stop)
    stop_api
    ;;
  restart)
    stop_api || true
    check_net || true
    ensure_base_pkgs
    ensure_python
    ensure_python_venv_ready
    clone_or_update
    prepare_venv_and_deps
    load_csv
    start_api_bg
    ;;
  status)
    status_api
    ;;
  logs)
    logs_follow
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs}"
    exit 1
    ;;
esac
