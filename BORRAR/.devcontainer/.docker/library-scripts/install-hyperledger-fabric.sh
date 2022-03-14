#!/bin/bash

CHANNEL_NAME=${1:-"mychannel"}
CCP_FILE_PATH=${2:-"../asset-transfer-basic/chaincode-go"}

CURRENT_DIR=$PWD
DIR=$GOPATH/src/github.com/devcontainer
mkdir -p $DIR
cd $DIR

curl -sSL https://bit.ly/2ysbOFE | bash -s


#Levantado postgresql 
service postgresql start
sudo -u postgres psql -c '\l'

# nvm install 16.4
# nvm use 16.4

# npm install -g npm@8.5.2 

# export DATABASE_HOST=127.0.0.1
# export DATABASE_PORT=5432
# export DATABASE_DATABASE=fabricexplorer
# export DATABASE_USERNAME=hppoc
# export DATABASE_PASSWD=pass12345