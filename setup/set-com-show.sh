#!/usr/bin/env bash

PID=$(lsof -ti tcp:8003 || true)

if [ -n "$PID" ]; then
  echo "포트 8003 사용 중 -> PID: $PID 종료"
  sudo kill -9 $PID
else
  echo "포트 8003 사용 중인 프로세스 없음"
fi

git clone https://github.com/BOB-DSPM/DSPM_Compliance-show
ls
cd DSPM_Compliance-show

python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt

# 스키마 마이그레이션(requirements 재생성 + threat_groups 테이블)
python migrate_sqlite_requirements.py

# 기본 CSV 로드
python -m scripts.load_csv --requirements ./compliance-gorn.csv --mappings ./mapping-standard.csv

# 위협그룹 CSV 로드(102개 매핑) — threat_groups.csv가 있는 경우
python scripts/load_threat_groups.py ./threat_groups.csv

# 서비스 기동
nohup python -m app.main > com-show.log 2>&1 & echo $! > com-show.pid
