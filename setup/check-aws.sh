#!/usr/bin/env bash
# collector_setup.sh — DSPM_Data-Collector 클론 → Steampipe 설치/실행 → Python API 0.0.0.0:8000 백그라운드 기동

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/BOB-DSPM/DSPM_Data-Collector.git}"
BRANCH="${BRANCH:-main}"
TARGET_DIR="${TARGET_DIR:-DSPM_Data-Collector}"

API_HOST="${HOST:-0.0.0.0}"
API_PORT="${PORT:-8000}"
FORCE_RESTART="${FORCE_RESTART:-1}"

log()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

SUDO=""; if [ "${EUID:-$(id -u)}" -ne 0 ] && command -v sudo >/devnull 2>&1; then SUDO="sudo"; fi

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
    *)      err "패키지 매니저 인식 실패 — 수동 설치 필요";;
  esac
  ok "git 설치 완료: $(git --version)"
}

ensure_python() {
  if command -v python3 >/dev/null 2>&1; then ok "python3: $(python3 --version)"; return; fi
  local pm; pm="$(detect_pm)"; check_net || true
  case "$pm" in
    apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y python3 python3-venv python3-pip ;;
    dnf|yum)$SUDO "$pm" install -y python3 python3-pip ;;
    pacman) $SUDO pacman -Sy --noconfirm python python-pip ;;
    zypper) $SUDO zypper --non-interactive install python3 python3-pip python3-venv || $SUDO zypper --non-interactive install python311 python311-pip ;;
    brew)   brew update; brew install python ;;
    *)      err "Python 설치 불가 — 수동 설치 필요";;
  esac
  ok "python3 설치 완료: $(python3 --version)"
}

ensure_steampipe() {
  # 사용자 홈 설치(기본: ~/.steampipe/bin/steampipe) → PATH 추가
  export PATH="$HOME/.steampipe/bin:$HOME/.local/bin:$PATH"
  if command -v steampipe >/dev/null 2>&1; then
    ok "steampipe: $(steampipe -v | head -n1)"
  else
    check_net || true
    log "Steampipe 설치(유저 영역: ~/.steampipe)"
    # 공식 install 스크립트(경로 자동 결정). '-b' 인자로 인해 404 나는 이슈를 피하기 위해 기본 설치 사용.
    if ! curl -fsSL https://raw.githubusercontent.com/turbot/steampipe/main/scripts/install.sh | bash; then
      err "Steampipe 설치 실패"; exit 1
    fi
    export PATH="$HOME/.steampipe/bin:$PATH"
    command -v steampipe >/dev/null 2>&1 || { err "steampipe PATH 반영 실패"; exit 1; }
    ok "steampipe: $(steampipe -v | head -n1)"
    # 쉘 로그인 시 PATH 자동 반영
    if ! grep -q '.steampipe/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.steampipe/bin:$PATH"' >> "$HOME/.bashrc"
    fi
  fi

  # AWS 플러그인
  if steampipe plugin list 2>/dev/null | grep -q '^aws'; then
    ok "steampipe aws 플러그인 설치됨"
  else
    log "steampipe aws 플러그인 설치"; steampipe plugin install aws
  fi

  # 서비스
  if steampipe service status 2>/dev/null | grep -qi "running"; then
    ok "steampipe service 이미 실행 중"
  else
    log "steampipe service start"; steampipe service start
    steampipe service status >/dev/null 2>&1 || { err "steampipe service 기동 실패"; exit 1; }
    ok "steampipe service 실행"
  fi
}

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
    log "레포 클론: $REPO_URL → $TARGET_DIR (브랜치: $BRANCH)"
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
      if [ "$FORCE_RESTART" = "1" ]; then
        warn "기존 API 실행 감지(PID=${old_pid}) → 종료 후 재시작"
        kill "$old_pid" || true; sleep 1
      else
        ok "API 이미 실행 중(PID=${old_pid})"; return 0
      fi
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

main() {
  check_net || true
  ensure_git
  ensure_python
  ensure_steampipe           # ← Steampipe는 여기서만 처리
  clone_or_update
  run_api_bg
}
main "$@"
