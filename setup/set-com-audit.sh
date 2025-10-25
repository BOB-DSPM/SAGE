
PID=$(lsof -ti tcp:8103 || true)

if [ -n "$PID" ]; then
  echo "포트 8103 사용 중 -> PID: $PID 종료"
  sudo kill -9 $PID
else
  echo "포트 8103 사용 중인 프로세스 없음"
fi

git clone https://github.com/BOB-DSPM/DSPM_Compliance-audit-fix
ls
cd DSPM_Compliance-audit-fix
python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt

nohup uvicorn app.main:app --host 0.0.0.0 --port 8103 --reload > com-audit.log 2>&1 & echo $! > com-audit.pid
