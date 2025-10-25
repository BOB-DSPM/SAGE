PID=$(lsof -ti tcp:8000 || true)

if [ -n "$PID" ]; then
  echo "포트 8000 사용 중 -> PID: $PID 종료"
  sudo kill -9 $PID
else
  echo "포트 8000 사용 중인 프로세스 없음"
fi

git clone https://github.com/BOB-DSPM/DSPM_Data-Collector

cd DSPM_Data-Collector

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

nohup python -m uvicorn main:app --host 0.0.0.0 --port 8000 > backend.log 2>&1 & echo $! > backend.pid
