PID=$(lsof -ti tcp:9000 || true)

if [ -n "$PID" ]; then
  echo "포트 9000 사용 중 -> PID: $PID 종료"
  sudo kill -9 $PID
else
  echo "포트 9000 사용 중인 프로세스 없음"
fi

# 1) 레포 클론
git clone --branch analyzer --single-branch https://github.com/BOB-DSPM/DSPM_DATA-Identification-Classification.git DSPM_DATA-IC-analyzer
cd DSPM_DATA-IC-analyzer

# 2) 가상환경 생성 및 활성화
python3 -m venv .venv
# macOS/Linux
source .venv/bin/activate

# 3) 필수 패키지 설치
cd dspm-analyzer
pip install -r requirements.txt
pip install fastapi uvicorn[standard]

nohup python -m uvicorn server:app --host 0.0.0.0 --port 9000 > analyzer.log 2>&1 & echo $! > analyzer.pid
