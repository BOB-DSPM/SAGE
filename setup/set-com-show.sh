
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

PYTHONPATH=. python3 scripts/load_csv.py \
  --requirements requirements.csv \
  --mappings mappings.csv \
  --threats threats.csv \
  --format auto \
  --encoding utf-8-sig

# 서비스 기동
nohup python3 -m app.main > com-show.log 2>&1 & echo $! > com-show.pid
