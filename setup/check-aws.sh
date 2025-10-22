#!/usr/bin/env bash
# check-aws.sh
# 목적: (1) 필수 패키지(curl, unzip 등) 보장 → (2) AWS CLI 설치/검증 → (3) 필요 시 aws configure 입력
# 사용법: ./setup/check-aws.sh  (configure 단계에서만 입력 받음)

set -euo pipefail

AWS_PROFILE="default"      # 기본 프로파일
FORCE_AWS_CONFIG="${FORCE_AWS_CONFIG:-0}"  # 1이면 항상 재설정

log()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }

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
  warn "네트워크 불안정 — 설치가 실패할 수 있습니다."
}

ensure_base_pkgs() {
  local pm; pm="$(detect_pm)"
  check_net || true
  local -a need=()
  command -v curl  >/dev/null 2>&1 || need+=("curl")
  command -v unzip >/dev/null 2>&1 || need+=("unzip")
  if [ "${#need[@]}" -eq 0 ]; then ok "필수 패키지 이미 설치됨"; return; fi
  log "필수 패키지 설치: ${need[*]}"
  case "$pm" in
    apt)    DEBIAN_FRONTEND=noninteractive $SUDO apt-get update -y; DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y "${need[@]}";;
    dnf|yum)$SUDO "$pm" install -y "${need[@]}";;
    pacman) $SUDO pacman -Sy --noconfirm "${need[@]}";;
    zypper) $SUDO zypper --non-interactive refresh; $SUDO zypper --non-interactive install "${need[@]}";;
    brew)   for p in "${need[@]}"; do brew list --versions "$p" >/dev/null 2>&1 || brew install "$p"; done;;
    *)      err "패키지 매니저 인식 실패 — 수동 설치 필요";;
  esac
  ok "필수 패키지 설치 완료"
}

install_awscli() {
  check_net || true
  local os="$(uname -s)" arch="$(uname -m)"
  if [ "$os" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    log "Homebrew로 AWS CLI 설치"; brew update; brew install awscli; return
  fi
  local url=""
  case "$arch" in
    x86_64|amd64)  url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
    aarch64|arm64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
    *)
      warn "알 수 없는 아키텍처(${arch}) → 패키지 매니저로 설치 시도"
      local pm; pm="$(detect_pm)"
      case "$pm" in
        apt)    $SUDO apt-get update -y; $SUDO apt-get install -y awscli ;;
        dnf|yum)$SUDO "$pm" install -y awscli ;;
        pacman) $SUDO pacman -Sy --noconfirm aws-cli ;;
        zypper) $SUDO zypper --non-interactive install aws-cli ;;
        brew)   brew install awscli ;;
        *)      err "AWS CLI 설치 경로 결정을 못했습니다."; exit 1;;
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
  echo; echo "=== aws configure (${AWS_PROFILE}) ==="
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

main() {
  ensure_base_pkgs
  ensure_awscli
  configure_aws_if_needed
  ok "완료! 이제 수집기/Steampipe는 collector_setup.sh로 실행하세요:"
  echo "  ./setup/collector_setup.sh"
}
main "$@"
