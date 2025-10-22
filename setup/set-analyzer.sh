#!/usr/bin/env bash
# setup-analyzer.sh
# - Clone BOB-DSPM/DSPM_DATA-Identification-Classification (branch: analyzer)
# - Create & activate .venv
# - pip install requirements + extras (presidio, ko_spacy, spacy)
# - uvicorn 백그라운드 실행/중지/상태/재시작
#
# 사용법:
#   bash setup-analyzer.sh run        # 설치+실행(최초 1회 또는 업데이트)
#   bash setup-analyzer.sh start      # 실행만
#   bash setup-analyzer.sh stop       # 중지
#   bash setup-analyzer.sh restart    # 재시작
#   bash setup-analyzer.sh status     # 상태 확인
#
# 환경변수(선택):
#   REPO_BRANCH=analyzer
#   REPO_DIR=DSPM_DATA-Identification-Classification
#   WORKDIR=dspm-analyzer             # 프로젝트 내 uvicorn 실행 기준 폴더
#   APP_MODULE="app.main:app"         # uvicorn 대상 모듈 경로(자동탐색 실패 시 지정)
#   PORT=8400
#   HOST=0.0.0.0
#   RELOAD=1                          # 1이면 --reload 사용
#   INSTALL_KO_MODELS=0               # 1이면 ko_spacy 관련 모델 설치 시도
#   PYTHON_BIN=python3

set -euo pipefail

### ========= 기본 설정 =========
REPO_URL="https://github.com/BOB-DSPM/DSPM_DATA-Identification-Classification.git"
REPO_BRANCH="${REPO_BRANCH:-analyzer}"
REPO_DIR="${REPO_DIR:-DSPM_DATA-Identification-Classification}"
WORKDIR="${WORKDIR:-dspm-analyzer}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8400}"
RELOAD="${RELOAD:-1}"
APP_MODULE="${APP_MODULE:-}"
INSTALL_KO_MODELS="${INSTALL_KO_MODELS:-0}"

LOG_DIR="${LOG_DIR:-logs}"
PID_FILE="${PID_FILE:-${LOG_DIR}/uvicorn_${PORT}.pid}"
OUT_FILE="${OUT_FILE:-${LOG_DIR}/uvicorn_${PORT}.out}"

### ========= 공통 유틸 =========
log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log "필요 명령어가 없습니다: $1"; return 1; }
}

install_if_missing() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    log "APT 설치: $pkg"
    sudo apt-get update -y
    sudo apt-get install -y "$pkg"
  fi
}

ensure_python_venv() {
  if ! "$PYTHON_BIN" -m venv --help >/dev/null 2>&1; then
    if grep -qiE "ubuntu|debian" /etc/os-release; then
      install_if_missing python3-venv
    else
      log "python venv 모듈이 필요합니다. OS 패키지로 설치 후 재시도하세요."
      exit 1
    fi
  fi
}

activate_venv() {
  # shellcheck disable=SC1091
  . "${VENV_DIR}/bin/activate"
}

is_running() {
  # PID 파일 기반
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && ps -p "${pid}" >/dev/null 2>&1; then
      return 0
    fi
  fi
  # 포트 리슨 기반(보조)
  if command -v lsof >/dev/null 2>&1 && lsof -i TCP:"${PORT}" -sTCP:LISTEN -t >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

### ========= 핵심 로직 =========
clone_or_update() {
  need_cmd git || { install_if_missing git; }

  if [[ -d "${REPO_DIR}/.git" ]]; then
    log "기존 레포 발견 → 업데이트: ${REPO_DIR} (branch: ${REPO_BRANCH})"
    git -C "${REPO_DIR}" fetch origin "${REPO_BRANCH}" --depth=1
    git -C "${REPO_DIR}" checkout -q "${REPO_BRANCH}"
    git -C "${REPO_DIR}" reset --hard "origin/${REPO_BRANCH}"
  else
    log "레포 클론: ${REPO_URL} (branch: ${REPO_BRANCH})"
    git clone --branch "${REPO_BRANCH}" --depth 1 "${REPO_URL}" "${REPO_DIR}"
  fi
}

make_venv_and_install() {
  need_cmd "${PYTHON_BIN}" || install_if_missing python3

  ensure_python_venv
  cd "${REPO_DIR}"
  if [[ ! -d "${VENV_DIR}" ]]; then
    log "가상환경 생성: ${VENV_DIR}"
    "${PYTHON_BIN}" -m venv "${VENV_DIR}"
  else
    log "가상환경 존재: ${VENV_DIR}"
  fi
  activate_venv
  python -m pip install --upgrade pip setuptools wheel

  # requirements 설치 (프로젝트 루트에 있거나 WORKDIR 내에 있을 수 있음)
  if [[ -f "requirements.txt" ]]; then
    log "의존성 설치: ./requirements.txt"
    pip install -r requirements.txt
  fi

  if [[ -d "${WORKDIR}" ]]; then
    cd "${WORKDIR}"
  fi

  if [[ -f "requirements.txt" ]]; then
    log "의존성 설치: ${WORKDIR}/requirements.txt"
    pip install -r requirements.txt
  fi

  # 추가 패키지(요청 사항)
  log "추가 패키지 설치 (presidio-analyzer, presidio-anonymizer, ko_spacy, spacy)"
  pip install -U presidio-analyzer presidio-anonymizer ko_spacy spacy

  if [[ "${INSTALL_KO_MODELS}" == "1" ]]; then
    # 한국어 토크나이저/모델 보강(가능한 경우에만)
    log "한국어 모델 설치 시도(spacy ko_core_news_sm)"
    python - <<'PY'
import subprocess, sys
try:
    import spacy
    subprocess.check_call([sys.executable, "-m", "spacy", "download", "ko_core_news_sm"])
except Exception as e:
    print("[warn] spaCy ko_core_news_sm 설치 스킵/실패:", e)
PY
  fi
}

auto_detect_app_module() {
  # 이미 지정된 경우 우선
  if [[ -n "${APP_MODULE}" ]]; then
    log "APP_MODULE 지정됨 → ${APP_MODULE}"
    return 0
  fi

  # 흔한 후보들(프로젝트 구조에 맞춰 늘리고/조정)
  local candidates=(
    "app.main:app"
    "api:app"
    "api.main:app"
    "main:app"
    "server:app"
    "src/app/main:app"
    "backend/main:app"
  )

  log "uvicorn APP_MODULE 자동 탐색..."
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
      log "탐색 성공 → APP_MODULE=${APP_MODULE}"
      return 0
    fi
  done

  log "⚠️ APP_MODULE 자동 탐색 실패. 환경변수 APP_MODULE로 지정하세요. 예) APP_MODULE='app.main:app'"
  exit 2
}

start_uvicorn() {
  mkdir -p "${LOG_DIR}"

  if is_running; then
    log "이미 uvicorn이 실행 중입니다. (포트:${PORT})"
    return 0
  fi

  local reload_flag=()
  [[ "${RELOAD}" == "1" ]] && reload_flag+=( "--reload" )

  log "uvicorn 백그라운드 시작 → ${APP_MODULE} (${HOST}:${PORT})"
  nohup python -m uvicorn "${APP_MODULE}" --host "${HOST}" --port "${PORT}" \
        "${reload_flag[@]}" >"${OUT_FILE}" 2>&1 &

  echo $! > "${PID_FILE}"
  sleep 0.7

  if is_running; then
    log "실행 성공: PID $(cat "${PID_FILE}") / 로그: ${OUT_FILE}"
  else
    log "실행 실패. 로그 확인: ${OUT_FILE}"
    exit 1
  fi
}

stop_uvicorn() {
  local stopped="false"
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && ps -p "${pid}" >/dev/null 2>&1; then
      log "PID ${pid} 종료"
      kill "${pid}" || true
      sleep 0.5
      if ps -p "${pid}" >/dev/null 2>&1; then
        log "강제 종료 시도"
        kill -9 "${pid}" || true
      fi
      stopped="true"
    fi
    rm -f "${PID_FILE}" || true
  fi

  if command -v lsof >/dev/null 2>&1; then
    local pids
    pids="$(lsof -i TCP:"${PORT}" -sTCP:LISTEN -t 2>/dev/null || true)"
    if [[ -n "${pids}" ]]; then
      log "포트 ${PORT} 점유 프로세스 종료: ${pids}"
      kill ${pids} 2>/dev/null || true
      sleep 0.5
      for p in ${pids}; do
        ps -p "${p}" >/dev/null 2>&1 && kill -9 "${p}" 2>/dev/null || true
      done
      stopped="true"
    fi
  fi

  if [[ "${stopped}" == "true" ]]; then
    log "정상적으로 중지되었습니다."
  else
    log "실행 중인 프로세스를 찾지 못했습니다."
  fi
}

status_uvicorn() {
  if is_running; then
    local pid="(알 수 없음)"
    [[ -f "${PID_FILE}" ]] && pid="$(cat "${PID_FILE}" 2>/dev/null || echo "(알 수 없음)")"
    log "실행 중: PID ${pid}, 포트 ${PORT}"
  else
    log "정지 상태"
  fi
}

healthcheck() {
  # 프로젝트마다 엔드포인트가 다를 수 있으므로 /health → /docs 순으로 간단 확인
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
      log "헬스체크 OK: /health"
    elif curl -fsS "http://127.0.0.1:${PORT}/docs" >/dev/null 2>&1; then
      log "헬스체크 OK: /docs"
    else
      log "헬스체크 실패(엔드포인트 다를 수 있음). 수동 확인 권장."
    fi
  else
    log "curl 없음 → 헬스체크 스킵"
  fi
}

### ========= 엔트리포인트 =========
run_all() {
  clone_or_update
  make_venv_and_install

  # uvicorn 실행 기준 디렉터리 진입
  cd "${REPO_DIR}"
  [[ -d "${WORKDIR}" ]] && cd "${WORKDIR}"

  auto_detect_app_module
  start_uvicorn
  healthcheck
  log "접속 URL: http://${HOST}:${PORT}"
}

case "${1:-run}" in
  run)
    run_all
    ;;
  start)
    cd "${REPO_DIR}" 2>/dev/null || true
    [[ -d "${WORKDIR}" ]] && cd "${WORKDIR}"
    activate_venv 2>/dev/null || true
    [[ -z "${APP_MODULE}" ]] && auto_detect_app_module
    start_uvicorn
    ;;
  stop)
    stop_uvicorn
    ;;
  restart)
    stop_uvicorn
    cd "${REPO_DIR}" 2>/dev/null || true
    [[ -d "${WORKDIR}" ]] && cd "${WORKDIR}"
    activate_venv 2>/dev/null || true
    [[ -z "${APP_MODULE}" ]] && auto_detect_app_module
    start_uvicorn
    ;;
  status)
    status_uvicorn
    ;;
  *)
    echo "사용법: $0 [run|start|stop|restart|status]"
    exit 1
    ;;
esac
