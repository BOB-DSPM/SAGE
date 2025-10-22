#!/usr/bin/env bash
# run_lineage.sh — DSPM Lineage API 설치/실행 스크립트
# 사용법:
#   ./run_lineage.sh            # 기본: 설치 + 백그라운드 실행
#   ./run_lineage.sh stop       # 중지
#   ./run_lineage.sh restart    # 재시작
#   ./run_lineage.sh status     # 상태 확인

set -euo pipefail

### ==========================
### 설정
### ==========================
REPO_URL="https://github.com/BOB-DSPM/DSPM_DATA-Lineage-Tracking.git"
REPO_DIR="${REPO_DIR:-DSPM_DATA-Lineage-Tracking}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="${VENV_DIR:-.venv}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8300}"
LOG_DIR="${LOG_DIR:-logs}"
PID_FILE="${PID_FILE:-.uvicorn.pid}"
UVICORN_CMD=( "${PYTHON_BIN}" -m uvicorn api:app --reload --host "${HOST}" --port "${PORT}" )

### ==========================
### 공통 함수
### ==========================
msg() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "필요한 명령어가 없습니다: $1" >&2
    exit 1
  }
}

ensure_python_venv() {
  # python3-venv 미설치로 venv 실패하는 환경(우분투 등) 대비
  if ! "${PYTHON_BIN}" -m venv --help >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
      msg "python3-venv가 없어 설치합니다 (sudo 권한 필요할 수 있음)"
      sudo apt update -y
      sudo apt install -y python3-venv
    else
      echo "python3-venv 모듈이 필요합니다. OS의 패키지 매니저로 설치 후 다시 시도하세요." >&2
      exit 1
    fi
  fi
}

activate_venv() {
  # shellcheck disable=SC1091
  . "${VENV_DIR}/bin/activate"
}

is_running() {
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && ps -p "${pid}" >/dev/null 2>&1; then
      return 0
    fi
  fi
  # 보조: 포트 기반 확인
  if command -v lsof >/dev/null 2>&1 && lsof -i TCP:"${PORT}" -sTCP:LISTEN -t >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

start() {
  mkdir -p "${LOG_DIR}"
  if is_running; then
    msg "이미 실행 중으로 보입니다. (포트:${PORT})"
    status
    return 0
  fi
  msg "Uvicorn 백그라운드 실행 시작"
  nohup "${UVICORN_CMD[@]}" >"${LOG_DIR}/lineage.out" 2>&1 &
  echo $! > "${PID_FILE}"
  sleep 0.7
  if is_running; then
    msg "실행 성공: PID $(cat "${PID_FILE}") / 로그: ${LOG_DIR}/lineage.out"
  else
    msg "실행에 실패했습니다. 로그를 확인하세요: ${LOG_DIR}/lineage.out"
    exit 1
  fi
}

stop() {
  local stopped="false"
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    if [[ -n "${pid}" ]] && ps -p "${pid}" >/dev/null 2>&1; then
      msg "PID ${pid} 종료"
      kill "${pid}" || true
      sleep 0.5
      if ps -p "${pid}" >/dev/null 2>&1; then
        msg "종료 신호 후에도 살아있어 강제 종료"
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
      msg "포트 ${PORT} 점유 프로세스 종료: ${pids}"
      kill ${pids} 2>/dev/null || true
      sleep 0.5
      # 남아있으면 강제
      for p in ${pids}; do
        if ps -p "${p}" >/dev/null 2>&1; then
          kill -9 "${p}" 2>/dev/null || true
        fi
      done
      stopped="true"
    fi
  fi

  if [[ "${stopped}" == "true" ]]; then
    msg "정상적으로 중지되었습니다."
  else
    msg "실행 중인 프로세스를 찾지 못했습니다."
  fi
}

status() {
  if is_running; then
    local pid="(알 수 없음)"
    [[ -f "${PID_FILE}" ]] && pid="$(cat "${PID_FILE}" 2>/dev/null || echo "(알 수 없음)")"
    msg "실행 중: PID ${pid}, 포트 ${PORT}"
  else
    msg "정지 상태"
  fi
}

install_and_run() {
  need_cmd git
  need_cmd "${PYTHON_BIN}"

  # 1) 레포 가져오기/업데이트
  if [[ -d "${REPO_DIR}/.git" ]]; then
    msg "레포 존재: ${REPO_DIR} → 최신화(git pull)"
    git -C "${REPO_DIR}" pull --ff-only
  else
    msg "레포 클론: ${REPO_URL}"
    git clone "${REPO_URL}" "${REPO_DIR}"
  fi

  cd "${REPO_DIR}"

  # 2) 가상환경
  ensure_python_venv
  if [[ ! -d "${VENV_DIR}" ]]; then
    msg "가상환경 생성: ${VENV_DIR}"
    "${PYTHON_BIN}" -m venv "${VENV_DIR}"
  else
    msg "가상환경 존재: ${VENV_DIR}"
  fi
  activate_venv

  # 3) pip 최신화 & 의존성 설치
  msg "pip 업그레이드"
  python -m pip install --upgrade pip wheel setuptools
  if [[ -f "requirements.txt" ]]; then
    msg "의존성 설치: requirements.txt"
    python -m pip install -r requirements.txt
  else
    msg "requirements.txt를 찾지 못했습니다. 스킵합니다."
  fi

  # 4) 실행
  start
  msg "접속: http://${HOST}:${PORT}"
}

### ==========================
### 엔트리포인트
### ==========================
case "${1:-run}" in
  run)       install_and_run ;;
  stop)      stop ;;
  restart)   stop; start ;;
  status)    status ;;
  *)
    echo "알 수 없는 명령: ${1}"
    echo "사용법: $0 [run|stop|restart|status]"
    exit 1
    ;;
esac
