git clone https://github.com/BOB-DSPM/DSPM_Data-Collector

cd DSPM_Data-Collector

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

python -m uvicorn main:app host=0.0.0.0 port=8000 --reload