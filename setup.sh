sudo chmod +x ./setup/*
sudo ./setup/install-npm.sh
./setup/set-front.sh

./setup/install-aws.sh
./setup/install-python.sh

./setup/set-collect.sh
./setup/set-lineage.sh
./setup/set-com-show.sh
./setup/set-com-audit.sh