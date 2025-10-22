#!/usr/bin/env bash
# setup-analyzer.sh (ko_spacy 제거 + 한국어 대안 추가: stanza / spacy-udpipe)
# 사용법: bash setup-analyzer.sh
# 환경변수:
#   REPO_BRANCH=analyzer
#   REPO_DIR=DSPM_DATA-Identification-Classification
#   APP_MODULE="app.main:app"
#   PORT=8400

set -euo pipefail

REPO_URL="https://github.com/BOB-DSPM/DSPM_DATA-Identification-Classification.git"
REPO_BRANCH="${REPO_BRANCH:-analyzer}"
REPO_DIR="${REPO_DIR:-DSPM_DATA-Identification-Classification}"
PORT="${PORT:-8400}"
APP_MODULE="${APP_MODULE:-}"

log(){ printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }
need_cmd(){ command -v "$1" >/dev/null 2>&1; }

install_if_missing(){
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    log "APT 설치: $pkg"
    sudo apt-get update -y
    sudo apt-get install -y "$pkg"
  fi
}

# 0) 기본 도구
if grep -qiE "ubuntu|debian" /etc/os-release; then
  need_cmd git || install_if_missing git
  need_cmd python3 || install_if_missing python3
  python3 -m venv --help >/dev/null 2>&1 || install_if_missing python3-venv
  need_cmd gcc || install_if_missing build-essential
  install_if_missing python3-pip || true
fi

# 1) 레포
if [ -d "$REPO_DIR/.git" ]; then
  log "기존 레포 갱신: $REPO_DIR ($REPO_BRANCH)"
  git -C "$REPO_DIR" fetch origin "$REPO_BRANCH" --depth=1
  git -C "$REPO_DIR" checkout -q "$REPO_BRANCH"
  git -C "$REPO_DIR" reset --hard "origin/$REPO_BRANCH"
else
  log "레포 클론: $REPO_URL ($REPO_BRANCH)"
  git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# 2) venv
if [ ! -d ".venv" ]; then
  log "가상환경 생성(.venv)"
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install -U pip setuptools wheel

# 3) 의존성
if [ -f requirements.txt ]; then
  log "requirements.txt 설치"
  pip install -r requirements.txt
fi

log "Presidio 최신 버전 설치/업그레이드"
pip install -U "presidio-analyzer==2.2.360" "presidio-anonymizer==2.2.360"

log "한국어 NLP 대안 설치 (stanza / spacy-udpipe) + 다국어 spacy 모델"
pip install -U spacy stanza spacy-udpipe

# 4) 한국어/멀티 모델 다운로드
log "한국어 모델 다운로드 (stanza ko, spacy-udpipe ko), 다국어 spacy 소형 NER"
python - <<'PY'
import stanza, subprocess, sys
# stanza ko
stanza.download('ko', processors='tokenize,pos,lemma,ner', verbose=False)
# spacy-udpipe ko
subprocess.run([sys.executable, "-m", "spacy_udpipe", "download", "ko"], check=True)
# spacy 다국어 소형 NER
subprocess.run([sys.executable, "-m", "spacy", "download", "xx_ent_wiki_sm"], check=False)
PY

# 5) uvicorn APP_MODULE 자동 탐색 (없으면 환경변수로 지정 요망)
if [ -z "$APP_MODULE" ]; then
  candidates=(
    "app.main:app"
    "src/app/main:app"
    "backend/main:app"
    "main:app"
    "server:app"
    "api.main:app"
  )
  for mod in "${candidates[@]}"; do
    if python - <<PY
import importlib, sys
m,a="$mod".split(":")
try:
    module=importlib.import_module(m)
    assert hasattr(module,a)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
    then APP_MODULE="$mod"; break; fi
  done
  if [ -z "$APP_MODULE" ]; then
    log "⚠️ uvicorn 진입 모듈을 찾지 못했습니다. APP_MODULE='app.main:app' 형태로 지정하세요."
    exit 2
  fi
fi

# 6) uvicorn 백그라운드 실행
mkdir -p logs
log "uvicorn 백그라운드 실행 → $APP_MODULE (0.0.0.0:${PORT})"
nohup python -m uvicorn "$APP_MODULE" --host 0.0.0.0 --port "$PORT" \
  > "logs/uvicorn_${PORT}.out" 2>&1 &

UVICORN_PID=$!
echo "$UVICORN_PID" > "logs/uvicorn_${PORT}.pid"
log "PID: $UVICORN_PID"
log "로그: $(pwd)/logs/uvicorn_${PORT}.out"
log "헬스체크: curl -i http://127.0.0.1:${PORT}/docs"
