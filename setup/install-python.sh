sudo apt update -y
sudo apt install python3.11 python3-pip -y
sudo apt install python3-venv -y


sudo /bin/sh -c "$(curl -fsSL https://steampipe.io/install/steampipe.sh)"

steampipe plugin install aws

steampipe service start