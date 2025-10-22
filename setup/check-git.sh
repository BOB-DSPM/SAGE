#!/usr/bin/env bash
# setup.sh — Git 존재 여부 확인 → 없으면 설치 → 있으면 다음 단계 실행
# 대상 OS: Ubuntu/Debian, RHEL/CentOS/Alma/Rocky, Amazon Linux, Fedora, Arch, openSUSE, macOS, Windows(WSL/Chocolatey)

set -euo pipefail

### =============== 공용 출력 ===============
log()   { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()   { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }
ok()    { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }

### =============== 권한/도구 보조 ===============
SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    warn "root 권한이 아님 && sudo 미설치. 가능한 경우 root로 재실행하세요."
  fi
fi

# 패키지 관리자 감지
detect_pm() {
  if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
  if command -v dnf >/dev/null 2>&1; then echo "dnf"; return; fi
  if command -v yum >/dev/null 2>&1; then echo "yum"; return; fi
  if command -v pacman >/dev/null 2>&1; then echo "pacman"; return; fi
  if command -v zypper >/dev/null 2>&1; then echo "zypper"; return; fi
  if command -v brew >/dev/null 2>&1; then echo "brew"; return; fi
  if command -v choco >/dev/null 2>&1; then echo "choco"; return; fi
  echo "unknown"
}

# 네트워크 확인(패키지 설치 전 간단 체크)
check_network() {
  if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 || curl -s --max-time 3 https://github.com >/dev/null 2>&1; then
    return 0
  fi
  warn "네트워크 연결이 불안정합니다. 패키지 설치가 실패할 수 있습니다."
}

### =============== Git 설치 ===============
install_git() {
  local pm; pm="$(detect_pm)"
  check_network || true

  case "$pm" in
    apt)
      log "apt로 git 설치"
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y
      DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y git
      ;;
    dnf)
      log "dnf로 git 설치"
      $SUDO dnf install -y git
      ;;
    yum)
      log "yum로 git 설치"
      $SUDO yum install -y git
      ;;
    pacman)
      log "pacman으로 git 설치"
      $SUDO pacman -Sy --noconfirm git
      ;;
    zypper)
      log "zypper로 git 설치"
      $SUDO zypper --non-interactive refresh
      $SUDO zypper --non-interactive install git
      ;;
    brew)
      log "Homebrew로 git 설치 (macOS)"
      brew update
      brew install git
      ;;
    choco)
      log "Chocolatey로 git 설치 (Windows)"
      choco install git -y
      ;;
    *)
      err "지원하지 않는 환경입니다. 수동으로 Git을 설치하세요: https://git-scm.com/downloads"
      exit 1
      ;;
  esac
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    ok "git 이미 설치됨: $(git --version)"
  else
    warn "git 미설치 — 설치를 시작합니다."
    install_git
    if command -v git >/dev/null 2>&1; then
      ok "git 설치 완료: $(git --version)"
    else
      err "git 설치에 실패했습니다."
      exit 1
    fi
  fi
}

### =============== 실제 실행 로직 ===============
run_main() {
  # ↓↓↓ 여기부터 사용자의 실제 작업을 작성하세요. (예: 리포지토리 클론, 의존성 설치 등)
  # 예시:
  # REPO_URL="https://github.com/BOB-DSPM/SAGE.git"
  # [ -d "./SAGE" ] || git clone "$REPO_URL"
  # cd SAGE
  # ./stack.sh up
  log "다음 단계 실행 준비 완료 (git 사용 가능). 여기에 실제 실행 로직을 추가하세요."
}

### =============== 엔트리포인트 ===============
main() {
  ensure_git
  run_main
}

main "$@"
