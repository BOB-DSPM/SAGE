
PID=$(lsof -ti tcp:8800 || true)

if [ -n "$PID" ]; then
  echo "포트 8800 사용 중 -> PID: $PID 종료"
  sudo kill -9 $PID
else
  echo "포트 8800 사용 중인 프로세스 없음"
fi

git clone https://github.com/BOB-DSPM/DSPM_Opensource-Runner
ls
cd DSPM_Opensource-Runner
python3 -m venv .venv
ls -al
source .venv/bin/activate

pip install -r requirements.txt
sudo /bin/sh -c "$(curl -fsSL https://powerpipe.io/install/powerpipe.sh)"

nohup python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8800 > oss.log 2>&1 & echo $! > oss.pid
