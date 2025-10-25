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
HOST=0.0.0.0 PORT=8200 npm start &
