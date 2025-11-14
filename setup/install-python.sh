sudo apt update -y
sudo apt install python3.11 python3-pip -y
sudo apt install python3-venv -y


sudo curl -sL https://steampipe.io/install.sh | bash

sudo steampipe plugin install aws

sudo steampipe service start