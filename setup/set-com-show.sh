
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

# 기본 CSV 로드
python3 -m scripts.load_csv --requirements ./compliance-gorn.csv --mappings ./mapping-standard.csv

# 위협그룹 CSV 로드(102개 매핑) — threat_groups.csv가 있는 경우
python3 scripts/load_csv.py ./threat_groups.csv

# 서비스 기동
nohup python3 -m app.main > com-show.log 2>&1 & echo $! > com-show.pid
