sudo apt update -y
sudo apt install python3.11 python3-pip -y
sudo apt install python3-venv -y


curl -sL https://steampipe.io/install.sh | bash

steampipe plugin install aws

steampipe service start