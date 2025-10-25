set -ex
PID=$(lsof -ti tcp:8200)

if [ -n "$PID" ]; then
  echo "포트 8200 ㅅ용 중 -> PID: $PID 종료"
  sudo kill -9 $PID
else
  echo "포트 8200 사용 중인 프로세스 없음"
fi

git clone https://github.com/BOB-DSPM/SAGE-FRONT
cd SAGE-FRONT/dspm_dashboard
npm install
HOST=0.0.0.0 PORT=8200 npm start
