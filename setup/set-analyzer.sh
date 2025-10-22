#!/usr/bin/env bash
# setup-analyzer.sh
# - Clone BOB-DSPM/DSPM_DATA-Identification-Classification (branch: analyzer)
# - Create & activate .venv
# - pip install requirements + extras (presidio, ko_spacy)
# - Run uvicorn in background (default port: 8400)
#
# 사용법:
#   bash setup-analyzer.sh
# 환경변수(선택):
#   APP_MODULE="app.main:app"  # uvicorn 대상 FastAPI app 경로
#   PORT=8400                 # uvicorn 포트
#   REPO_DIR="DSPM_DATA-Identification-Classification"

set -euo pipefail

REPO_URL="https://github.com/BOB-DSPM/DSPM_DATA-Identification-Classification.git"
REPO_BRANCH="${REPO_BRANCH:-analyzer}"
REPO_DIR="${REPO_DIR:-DSPM_DATA-Identification-Classification}"
PORT="${PORT:-8400}"

# uvicorn에서 import할 모듈 경로 자동 추정 (필요 시 APP_MODULE로 덮어쓰기)
APP_MODULE="${APP_MODULE:-}"

log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "필요 명령어가 없어 설치 필요: $1"; return 1; }
}

install_if_missing() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    log "APT 설치: $pkg"
    sudo apt-get update -y
    sudo apt-get install -y "$pkg"
  fi
}

### 0) 필수 도구 확인/설치 (Ubuntu/Debian 가정)
if grep -qiE "ubuntu|debian" /etc/os-release; then
  need_cmd git || install_if_missing git
  need_cmd python3 || install_if_missing python3
  # venv 준비 (ensurepip 문제 대비)
  if ! python3 -m venv --help >/dev/null 2>&1; then
    install_if_missing python3-venv
  fi
  # 빌드 도구(일부 패키지 빌드 대비)
  need_cmd gcc || install_if_missing build-essential
  # 가상환경 내 wheel 빌드를 위한 pip 최신화 시 도움
  install_if_missing python3-pip || true
fi

### 1) 레포 클론/갱신
if [ -d "$REPO_DIR/.git" ]; then
  log "기존 레포 발견 → 갱신: $REPO_DIR"
  git -C "$REPO_DIR" fetch origin "$REPO_BRANCH" --depth=1
  git -C "$REPO_DIR" checkout -q "$REPO_BRANCH"
  git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH"
else
  log "레포 클론: $REPO_URL (branch: $REPO_BRANCH)"
  git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

### 2) Python 가상환경(.venv) 생성/활성화
if [ ! -d ".venv" ]; then
  log "가상환경 생성(.venv)"
  python3 -m venv .venv || {
    # 드물게 ensurepip 불가 시 재설치 후 재시도
    if grep -qiE "ubuntu|debian" /etc/os-release; then
      install_if_missing python3-venv
      python3 -m venv .venv
    else
      log "가상환경 생성 실패. python3-venv 설치 여부를 확인하세요."
      exit 1
    fi
  }
fi

# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install --upgrade pip setuptools wheel

cd dspm-analyzer
### 3) 의존성 설치 (requirements.txt + 추가 패키지)
if [ -f "requirements.txt" ]; then
  log "requirements.txt 설치"
  pip install -r requirements.txt
else
  log "requirements.txt 없음 → 건너뜀"
fi

log "추가 패키지 설치 (presidio-analyzer, presidio-anonymizer, ko_spacy)"
pip install -U presidio-analyzer presidio-anonymizer ko_spacy

# (선택) spaCy 본체가 없을 수도 있으니 보강
pip install -U spacy || true

### 4) uvicorn 앱 모듈 자동 탐색 (필요 시 APP_MODULE로 지정하여 건너뛰기)
if [ -z "$APP_MODULE" ]; then
  # 흔한 경로 후보들
  candidates=(
    "app.main:app"
    "src/app/main:app"
    "backend/main:app"
    "main:app"
    "server:app"
    "api.main:app"
  )

  # 간단한 import 확인기로 찾기
  for mod in "${candidates[@]}"; do
    if python - <<PY
import importlib, sys
m, a = "$mod".split(":")
try:
    module = importlib.import_module(m)
    assert hasattr(module, a)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
    then
      APP_MODULE="$mod"
      break
    fi
  done

  # 그래도 못 찾으면 사용자 수동 지정 유도
  if [ -z "$APP_MODULE" ]; then
    log "⚠️ uvicorn 진입 모듈을 자동으로 찾지 못했습니다."
    log "환경변수 APP_MODULE 로 지정하세요. 예) APP_MODULE='app.main:app'"
    # 일단 안전하게 종료
    exit 2
  fi
fi

### 5) uvicorn 백그라운드 실행 (nohup)
mkdir -p logs
log "uvicorn 백그라운드 실행 → $APP_MODULE (0.0.0.0:${PORT})"
nohup python -m uvicorn "$APP_MODULE" --host 0.0.0.0 --port "$PORT" \
  > "logs/uvicorn_${PORT}.out" 2>&1 &

UVICORN_PID=$!
echo "$UVICORN_PID" > "logs/uvicorn_${PORT}.pid"
log "PID: $UVICORN_PID"
log "로그: $(pwd)/logs/uvicorn_${PORT}.out"
log "헬스체크 예: curl -i http://127.0.0.1:${PORT}/docs 또는 /health (엔드포인트에 따라 다름)"

# 끝.
