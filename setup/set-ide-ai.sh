
PID=$(lsof -ti tcp:8900 || true)

if [ -n "$PID" ]; then
  echo "포트 8900 사용 중 -> PID: $PID 종료"
  sudo kill -9 $PID
else
  echo "포트 8900 사용 중인 프로세스 없음"
fi

git clone https://github.com/BOB-DSPM/SAGE_Identity-AI
ls
cd SAGE_Identity-AI
python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt
pip install torch --index-url https://download.pytorch.org/whl/cpu

sudo apt install wget tar
wget https://github.com/BOB-DSPM/SAGE_Identity-AI/releases/download/v0.1.0/xlmr-large-min.tar.zst
ls
tar --zstd -xf xlmr-large-min.tar.zst 
export MODEL_DIR=./xlmr-large-min
nohup python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8900 > iden-ai.log 2>&1 & echo $! > iden-ai.pid
