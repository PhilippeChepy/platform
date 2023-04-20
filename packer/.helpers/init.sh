#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

apt update -y
apt upgrade -yq
apt install curl sudo software-properties-common python3-pip openssh-client -yq
# python3-venv

curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

apt update -y
apt install -yq packer

# python3 -m venv .venv
# source .venv/bin/activate
pip3 install -r python-requirements.txt

bash
