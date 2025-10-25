
git clone https://github.com/BOB-DSPM/DSPM_DATA-Lineage-Tracking

cd DSPM_DATA_Lineage-Tracking
python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt

python -m uvicorn api:app --reload --port 8300