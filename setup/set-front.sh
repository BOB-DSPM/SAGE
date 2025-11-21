#!/usr/bin/env bash
set -ex

PID=$(lsof -ti tcp:8200 || true)

if [ -n "$PID" ]; then
  echo "포트 8200 사용 중 -> PID: $PID 종료"
  sudo kill -9 $PID
else
  echo "포트 8200 사용 중인 프로세스 없음"
fi

# 이미 클론되어 있으면 다시 안 받도록 처리
if [ ! -d "SAGE-FRONT" ]; then
  git clone https://github.com/BOB-DSPM/SAGE-FRONT
fi

cd SAGE-FRONT/dspm_dashboard
npm install
npm run build

# 기본 API 호스트(IP)는 외부에서 전달된 SAGE_HOST_IP 사용, 없으면 로컬
API_HOST="${SAGE_HOST_IP:-127.0.0.1}"
COLLECTOR_BASE="http://${API_HOST}:8000"
SHOW_BASE="http://${API_HOST}:8003"
AUDIT_BASE="http://${API_HOST}:8103"
LINEAGE_BASE="http://${API_HOST}:8300"
OSS_BASE="http://${API_HOST}:8800/oss"

nohup env \
  HOST=0.0.0.0 PORT=8200 \
  REACT_APP_API_HOST="${API_HOST}" \
  REACT_APP_INVENTORY_API_BASE="${COLLECTOR_BASE}" \
  REACT_APP_COLLECTOR_API_BASE="${COLLECTOR_BASE}" \
  REACT_APP_COMPLIANCE_API_BASE="${SHOW_BASE}" \
  REACT_APP_AUDIT_API_BASE="${AUDIT_BASE}" \
  REACT_APP_LINEAGE_API_BASE="${LINEAGE_BASE}" \
  REACT_APP_OSS_BASE="${OSS_BASE}" \
  REACT_APP_OSS_WORKDIR=/workspace \
  npm start > frontend.log 2>&1 &
