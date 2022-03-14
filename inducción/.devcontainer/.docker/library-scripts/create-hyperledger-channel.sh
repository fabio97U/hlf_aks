#!/bin/bash

CHANNEL_NAME=${1:-"mychannel"}

dir=$PWD

export TEST_NETWORK_PATH=$FABRIC_SAMPLES_DIR/test-network

YELLOW_COLLOR="\033[1;33m"

cd $TEST_NETWORK_PATH

./network.sh down
./network.sh up -s couchdb

echo "$YELLOW_COLLOR Creating a channel"
./network.sh createChannel -c $CHANNEL_NAME


sed -i "s|##CHANNEL_NAME##|${CHANNEL_NAME}|g" /smartcontract/local-ccp-template.yaml
sed -i "s|##FABRIC_SAMPLE_CONFIG_PATH##|${FABRIC_CFG_PATH}|g" /smartcontract/local-ccp-template.yaml
sed -i "s|##FABRIC_SAMPLE_USERS_CREDENTIAL_STORE_PATH##|${FABRIC_SAMPLES_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users|g" /smartcontract/local-ccp-template.yaml
sed -i "s|##FABRIC_SAMPLE_ADMIN_MSP_PATH##|${FABRIC_SAMPLES_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp|g" /smartcontract/local-ccp-template.yaml
sed -i "s|##CLIENT_CERT_FILE_PATH##|${FABRIC_SAMPLES_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/tls/client.crt|g" /smartcontract/local-ccp-template.yaml
sed -i "s|##CLIENT_CERT_KEY_PATH##|${FABRIC_SAMPLES_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/tls/client.key|g" /smartcontract/local-ccp-template.yaml
sed -i "s|##ORG1_CRYPTO_PATH##|${FABRIC_SAMPLES_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp|g" /smartcontract/local-ccp-template.yaml
sed -i "s|##ORG2_CRYPTO_PATH##|${FABRIC_SAMPLES_DIR}/test-network/organizations/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp|g" /smartcontract/local-ccp-template.yaml
sed -i "s|##PEERS_TLS_CA_CERT_PATH##|${FABRIC_SAMPLES_DIR}/test-network/organizations/peerOrganizations/org1.example.com/tlsca/tlsca.org1.example.com-cert.pem|g" /smartcontract/local-ccp-template.yaml

mkdir -p /workspaces/resources/config
cp /smartcontract/local-ccp-template.yaml /workspaces/resources/config/local-ccp.yaml

echo "$YELLOW_COLLOR Local CCP file created on /workspaces/resources/config/local-ccp.yaml"

cd $dir