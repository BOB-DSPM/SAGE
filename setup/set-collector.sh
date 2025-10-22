#!/usr/bin/env bash
# collector_setup.sh — DSPM_Data-Collector 클론 → Steampipe 설치/실행 → Python API(uvicorn) 0.0.0.0:8000 백그라운드 기동
# 대상 OS: Ubuntu/Debian, RHEL/CentOS/Alma/Rocky, Amazon Linux, Fedora, Arch, openSUSE, macOS

set -euo pipefail

### ===== 설정 =====
REPO_URL="${REPO_URL:-https://github.com/BOB-DSPM/DSPM_Data-Collector.git}"
BRANCH="${BRANCH:-main}"
TARGET_DIR="${TARGET_DIR:-DSPM_Data-Collector}"

API_HOST="${HOST:-0.0.0.0}"
API_PORT="${PORT:-8000}"
FORCE_RESTART="${FORCE_RESTART:-1}"   # 1이면 기존 프로세스 종료 후 재시작

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

### ===== 필수 패키지 보장 (curl, unzip, lsof) =====
ensure_base_pkgs() {
  local pm; pm="$(detect_pm)"
  local -a need=()
  command -v curl  >/dev/null 2>&1 || need+=("curl")
  command -v unzip >/dev/null 2>&1 || need+=("unzip")
  command -v lsof  >/dev/null 2>&1 || need+=("lsof")
  [ "${#need[@]}" -eq 0 ] && { ok "필수 패키지 이미 설치됨"; return; }
  log "필수 패키지 설치: ${need[*]}"
  case "$pm" in
    apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "${need[@]}";;
    dnf|yum)$SUDO "$pm" install -y "${need[@]}";;
    pacman) $SUDO pacman -Sy --noconfirm "${need[@]}";;
    zypper) $SUDO zypper --non-interactive refresh; $SUDO zypper --non-interactive install "${need[@]}";;
    brew)   for p in "${need[@]}"; do brew list --versions "$p" >/dev/null 2>&1 || brew install "$p"; done;;
    *)      err "패키지 매니저를 인식하지 못했습니다. 수동 설치 필요.";;
  esac
  ok "필수 패키지 설치 완료"
}

### ===== Git 보장 =====
ensure_git() {
  if command -v git >/dev/null 2>&1; then ok "git: $(git --version)"; return; fi
  local pm; pm="$(detect_pm)"; check_net || true
  case "$pm" in
    apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y git ca-certificates curl ;;
    dnf)    $SUDO dnf install -y git ca-certificates curl ;;
    yum)    $SUDO yum install -y git ca-certificates curl ;;
    pacman) $SUDO pacman -Sy --noconfirm git ca-certificates curl ;;
    zypper) $SUDO zypper --non-interactive refresh; $SUDO zypper --non-interactive install git ca-certificates curl ;;
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
      dnf|yum)$SUDO "${pm}" install -y python3 python3-pip ;;
      pacman) $SUDO pacman -Sy --noconfirm python python-pip ;;
      zypper) $SUDO zypper --non-interactive install python3 python3-pip python3-venv || $SUDO zypper --non-interactive install python311 python311-pip ;;
      brew)   brew update; brew install python ;;
      *)      err "Python 설치 불가한 환경입니다. 수동 설치 필요."; exit 1 ;;
    esac
    ok "python3 설치 완료: $(python3 --version)"
  fi
}
ensure_steampipe() {
  set -euo pipefail
  export PATH="$HOME/.local/bin:$HOME/.steampipe/bin:$PATH"

  if command -v steampipe >/dev/null 2>&1; then
    ok "steampipe: $(steampipe -v | head -n1)"
    return
  fi

  check_net || true
  log "Steampipe 수동 설치(사용자 영역: \$HOME/.local/bin)"

  # 아키텍처 판별
  local os arch pkg url tmpd bindir
  os="$(uname -s)"
  arch="$(uname -m)"
  bindir="$HOME/.local/bin"
  mkdir -p "$bindir"

  case "$os" in
    Linux)  os="linux"  ;;
    Darwin) os="darwin" ;;
    *) err "지원하지 않는 OS: $(uname -s)"; exit 1 ;;
  esac

  case "$arch" in
    x86_64|amd64)   arch="amd64"  ;;
    aarch64|arm64)  arch="arm64"  ;;
    *) err "지원하지 않는 아키텍처: $(uname -m)"; exit 1 ;;
  esac

  pkg="steampipe_${os}_${arch}.tar.gz"
  url="https://github.com/turbot/steampipe/releases/latest/download/${pkg}"

  tmpd="$(mktemp -d)"
  trap 'rm -rf "$tmpd"' EXIT

  log "다운로드: ${url}"
  curl -fsSL "$url" -o "$tmpd/steampipe.tgz"

  log "압축 해제"
  tar -xzf "$tmpd/steampipe.tgz" -C "$tmpd"

  # steampipe 단일 바이너리 복사
  install -m 0755 "$tmpd/steampipe" "$bindir/steampipe"

  # PATH 반영
  export PATH="$bindir:$PATH"
  if ! command -v steampipe >/dev/null 2>&1; then
    err "steampipe PATH 반영 실패 ($bindir 확인)"
    exit 1
  fi

  ok "steampipe 설치 완료: $(steampipe -v | head -n1)"

  # 로그인 쉘에 PATH 영구 반영
  if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  fi

  # 선택: sudo 가능하면 전역 심볼릭 링크(편의)
  if [ -n "${SUDO:-}" ]; then
    if ! [ -e /usr/local/bin/steampipe ] || [ -L /usr/local/bin/steampipe ]; then
      log "전역 링크: /usr/local/bin/steampipe → $bindir/steampipe"
      $SUDO ln -sf "$bindir/steampipe" /usr/local/bin/steampipe || true
    fi
  fi

  # 플러그인/서비스
  if steampipe plugin list 2>/dev/null | grep -q '^aws'; then
    ok "steampipe aws 플러그인 설치됨"
  else
    log "steampipe aws 플러그인 설치"
    steampipe plugin install aws
  fi

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
    git -C "$TARGET_DIR" fetch --all --prune
    git -C "$TARGET_DIR" checkout "$BRANCH"
    git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH" || git -C "$TARGET_DIR" pull --rebase origin "$BRANCH"
  else
    if [ -e "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR/.git" ]; then
      ts="$(date +%Y%m%d-%H%M%S)"; mv "$TARGET_DIR" "${TARGET_DIR}.bak-${ts}"; warn "동명 폴더 백업함"
    fi
    log "클론: $REPO_URL → $TARGET_DIR (브랜치: $BRANCH)"
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
  fi
  ok "레포 준비 완료: $TARGET_DIR"
}


run_api_bg() {
  # 1) DSPM 폴더로 이동
  cd "$TARGET_DIR"  || { err "디렉터리 없음: $TARGET_DIR"; exit 1; }
  mkdir -p logs

  # 2) 기존 백엔드가 돌고 있으면 종료(옵션)
  if [ -f ".pid" ]; then
    old_pid="$(cat .pid || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
      if [ "${FORCE_RESTART:-1}" = "1" ]; then
        warn "기존 API(PID=${old_pid}) 종료 후 재시작"
        kill "$old_pid" || true
        sleep 1
      else
        ok "API 이미 실행 중 (PID=${old_pid})"; return 0
      fi
    fi
  fi

  # 3) 가상환경 준비 및 활성화
  if [ ! -d ".venv" ]; then
    log "Python venv 생성(.venv)"
    python3 -m venv .venv
  fi
  # shellcheck disable=SC1091
  . ".venv/bin/activate"

  # 4) 패키지 설치 (requirements.txt 있으면 그걸, 없으면 최소 패키지)
  python -m pip install --upgrade pip >/dev/null
  if [ -f "requirements.txt" ]; then
    log "requirements 설치"
    pip install -r requirements.txt
  else
    log "requirements.txt 없음 → 최소 패키지 설치"
    pip install fastapi uvicorn steampipe
  fi

  # 5) uvicorn 백그라운드 실행 (로그/ PID 관리)
  ts="$(date +%Y%m%d-%H%M%S)"
  logfile="logs/collector-api-${ts}.log"

  ok "Collector API 백그라운드 시작: HOST=${API_HOST:-0.0.0.0} PORT=${API_PORT:-8000}"
  HOST="${API_HOST:-0.0.0.0}" PORT="${API_PORT:-8000}" \
    nohup python -m uvicorn main:app \
      --host "${API_HOST:-0.0.0.0}" \
      --port "${API_PORT:-8000}" \
      --reload \
      > "${logfile}" 2>&1 &

  echo "$!" > .pid
  ok "PID=$(cat .pid) (로그: ${logfile})"
  log "최근 로그: tail -n 200 -f ${logfile}"
  log "중지: kill \$(cat .pid)"
}



### ===== 엔트리포인트 =====
main() {
  check_net || true
  ensure_base_pkgs
  ensure_git
  ensure_python
  ensure_steampipe
  clone_or_update
  run_api_bg
}
main "$@"
