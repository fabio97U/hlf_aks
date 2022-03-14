# source byfn2.sh Azure https://github.com/Azure/Hyperledger-Fabric-on-Azure-Kubernetes-Service/blob/master/consortiumScripts/scripts/byn2.sh

CHAINCODE_NAME="mycc"
VERSION="1.0"
LANGUAGE="golang"
LOG_FILE="/tmp/log.txt"
DELAY=3
MAX_RETRY=10
COUNTER=1

function setPeerGlobals() {
   PEER=$1

  export CORE_PEER_LOCALMSPID="${HLF_ORG_NAME}"
  export CORE_PEER_ADDRESS="peer${PEER}.${HLF_DOMAIN_NAME}:443"
}

function verifyResult() {
  if [ $1 -ne 0 ]; then
    errorLog=$(tr -d '\n' < $LOG_FILE)
    echo "======== !!! HLF SCRIPT ERROR !!! "$2" !!! RETURN CODE: "$1" !!! ERROR LOG: $errorLog !!!! ==============="
    echo
    exit 1
  fi
}

function configAsOrderer() {
  export FABRIC_CFG_PATH=/var/hyperledger/ordererAdmin
  export CORE_PEER_MSPCONFIGPATH="${FABRIC_CFG_PATH}/msp"
  export HLF_ORG_NAME="${HLF_ORDERER_ORG_NAME}"
  export HLF_DOMAIN_NAME="${HLF_ORDERER_DOMAIN_NAME}"
  export HLF_NODE_COUNT="${HLF_ORDERER_NODE_COUNT}"
  export CORE_PEER_LOCALMSPID="${HLF_ORG_NAME}"
}

function configAsPeer() {
  export FABRIC_CFG_PATH=/var/hyperledger/admin
  export CORE_PEER_MSPCONFIGPATH="${FABRIC_CFG_PATH}/msp"
  export HLF_ORG_NAME="${HLF_PEER_ORG_NAME}"
  export HLF_DOMAIN_NAME="${HLF_PEER_DOMAIN_NAME}"
  export HLF_NODE_COUNT="${HLF_PEER_NODE_COUNT}"
  export CORE_PEER_LOCALMSPID="${HLF_ORG_NAME}"
}

function fetchChannelConfig() {
  CHANNEL=$1
  OUTPUT=$2

  setPeerGlobals 1

  echo "Fetching the most recent configuration block for the channel"
  set -x
  peer channel fetch config config_block.pb -o ${ORDERER_ADDRESS} -c $CHANNEL --tls --cafile ${ORDERER_TLS_CA} --clientauth --certfile $ADMIN_TLS_CERTFILE --keyfile $ADMIN_TLS_KEYFILE &> $LOG_FILE
  res=$?
  set +x
  cat $LOG_FILE
  verifyResult $res "Fetching Genesis block for the channel '${CHANNEL}' from '${ORDERER_ADDRESS}' orderer failed"
  
  echo "Decoding config block to JSON and isolating config to ${OUTPUT}"
  configtxlator proto_decode --input config_block.pb --type common.Block > config_common_block.json 2> $LOG_FILE
  res=$?
  verifyResult $res "Decoding config block to JSON failed"
  jq .data.data[0].payload.data.config config_common_block.json >"${OUTPUT}"
}

function createConfigUpdate() {
  CHANNEL=$1
  ORIGINAL=$2
  MODIFIED=$3
  OUTPUT=$4

  configtxlator proto_encode --input "${ORIGINAL}" --type common.Config --output original_config.pb 2> $LOG_FILE
  res=$?
  verifyResult $res "Converting original configuration block from JSON to Protobuf failed!!"

  configtxlator proto_encode --input "${MODIFIED}" --type common.Config --output modified_config.pb 2> $LOG_FILE
  res=$?
  verifyResult $res "Converting modified configuration block from JSON to Protobuf failed!!"

  configtxlator compute_update --channel_id "${CHANNEL}" --original original_config.pb --updated modified_config.pb --output config_update.pb 2> $LOG_FILE
  res=$?
  verifyResult $res "Computing difference between original and modified configuration block failed!!"

  configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate --output config_update.json 2> $LOG_FILE
  res=$?
  verifyResult $res "Converting configuration update from Protobuf to JSON failed!!"

  echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . >config_update_in_envelope.json
  configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope --output "${OUTPUT}" 2> $LOG_FILE
  res=$?
  verifyResult $res "Converting configuration update with envelop from JSON to Protobuf failed!!"
}

function createChannel() {
  configAsOrderer
  CHANNEL_NAME=$1

  if [[ ! "$CHANNEL_NAME" =~ ^[a-z][a-z0-9.-]*$ ]]; then
     echo "Invalid character in channel name!!!!"
     echo "Only 'a-z','0-9','.' and '-' is allowed in channel name!!!" 
     exit 1
  fi

  echo
  echo "========= Generating channel configuration transaction ============"
  echo
  configtxgen -profile SampleChannel -outputCreateChannelTx ./channel.tx -channelID $CHANNEL_NAME 2> $LOG_FILE
  res=$?
  verifyResult $res "Failed to generate channel configuration transaction"

  ORDERER_ADDRESS="orderer1.${HLF_DOMAIN_NAME}:443"

  setPeerGlobals 1
  ORDERER_TLS_CA="$FABRIC_CFG_PATH/tls/chain.crt"
  set -x
  peer channel create -o $ORDERER_ADDRESS -c $CHANNEL_NAME -f ./channel.tx --tls --cafile $ORDERER_TLS_CA --clientauth --certfile $ADMIN_TLS_CERTFILE --keyfile $ADMIN_TLS_KEYFILE &> $LOG_FILE
  res=$?
  set +x
  verifyResult $res "Channel creation failed"
  cat $LOG_FILE
  echo
  echo "===================== Channel '$CHANNEL_NAME' created ===================== "
  echo
}

function addPeerInConsortium() {
  configAsOrderer
  ORDERER_TLS_CA="$FABRIC_CFG_PATH/tls/chain.crt"
  ORDERER_ADDRESS="orderer1.${HLF_DOMAIN_NAME}:443"
  PEER_ORG_NAME=$1
  CHANNEL_NAME=$2

  configtxgen -printOrg ${PEER_ORG_NAME} > ${PEER_ORG_NAME}.json 2> $LOG_FILE
  res=$?
  verifyResult $res "Failed to generate ${PEER_ORG_NAME} config material"

  echo
  echo "========= Creating config transaction to add '${PEER_ORG_NAME}' to consortium =========== "
  echo
  # Fetch the config for the channel, writing it to config.json
  fetchChannelConfig ${CHANNEL_NAME} config.json

  # Modify the configuration to append the new org
  jq -s ".[0] * {\"channel_group\":{\"groups\":{\"Consortiums\":{\"groups\": {\"SampleConsortium\": {\"groups\": {\"${PEER_ORG_NAME}\":.[1]}}}}}}}" config.json ${PEER_ORG_NAME}.json > modified_config.json
  res=$?
  verifyResult $res "Failed to create new confguration block"

  echo
  echo "========= Compute config update based on difference between current and new configuration =========== "
  echo
  # Compute a config update, based on the differences between config.json and modified_config.json, write it as a transaction to {PEER_ORG_NAME}_update_in_envelope.pb
  createConfigUpdate ${CHANNEL_NAME} config.json modified_config.json ${PEER_ORG_NAME}_update_in_envelope.pb

  echo
  echo "========= Config transaction to add ${PEER_ORG_NAME} to network created ===== "
  echo

  echo
  echo "========= Submitting transaction from orderer admin which signs it as well ========= "
  echo
  set -x
  peer channel update -f ${PEER_ORG_NAME}_update_in_envelope.pb -c ${CHANNEL_NAME} -o ${ORDERER_ADDRESS} --tls --cafile ${ORDERER_TLS_CA} --clientauth --certfile $ADMIN_TLS_CERTFILE --keyfile $ADMIN_TLS_KEYFILE &> $LOG_FILE
  res=$?
  set +x
  cat $LOG_FILE
  verifyResult $res "peer channel update transaction failed"

  echo
  echo "========= Config transaction to add ${PEER_ORG_NAME} to network submitted! =========== "
  echo
}

function addPeerInChannel() {
  configAsOrderer
  PEER_ORG_NAME=$1
  CHANNEL_NAME=$2
  ORDERER_ADDRESS="orderer1.${HLF_DOMAIN_NAME}:443"
  
  echo "========== Generating ${PEER_ORG_NAME} config material ========="
  echo
  configtxgen -printOrg ${PEER_ORG_NAME} > ${PEER_ORG_NAME}.json 2> $LOG_FILE
  res=$?
  verifyResult $res "Failed to generate ${PEER_ORG_NAME} config material in JSON format"

  ORDERER_TLS_CA="$FABRIC_CFG_PATH/tls/chain.crt"

  echo
  echo "========= Creating config transaction to add ${PEER_ORG_NAME} to channel '${CHANNEL_NAME}' =========== "
  echo
  # Fetch the config for the channel, writing it to config.json
  fetchChannelConfig ${CHANNEL_NAME} config.json


  # Modify the configuration to append the new org
  jq -s ".[0] * {\"channel_group\":{\"groups\":{\"Application\":{\"groups\": {\"${PEER_ORG_NAME}\":.[1]}}}}}" config.json ${PEER_ORG_NAME}.json > modified_config.json
  res=$?
  verifyResult $res "Failed to generate new configuration block"

  echo
  echo "========= Compute config update based on difference between current and new configuration =========== "
  echo
  # Compute a config update, based on the differences between config.json and modified_config.json, write it as a transaction to org3_update_in_envelope.pb
  createConfigUpdate ${CHANNEL_NAME} config.json modified_config.json ${PEER_ORG_NAME}_update_in_envelope.pb

  echo
  echo "========= Config transaction to add ${PEER_ORG_NAME} to channel created ===== "
  echo

  echo
  echo "========= Submitting transaction from orderer admin which signs it as well ========= "
  echo
  set -x
  peer channel update -f ${PEER_ORG_NAME}_update_in_envelope.pb -c ${CHANNEL_NAME} -o ${ORDERER_ADDRESS} --tls --cafile ${ORDERER_TLS_CA} --clientauth --certfile $ADMIN_TLS_CERTFILE --keyfile $ADMIN_TLS_KEYFILE &> $LOG_FILE
  res=$?
  set +x
  cat $LOG_FILE
  verifyResult $res "peer channel update transaction failed"

  echo
  echo "========= Config transaction to add ${PEER_ORG_NAME} to channel ${CHANNEL_NAME} submitted! =========== "
  echo
}

function joinNodesInChannel() {
  configAsPeer
  CHANNEL_NAME=$1
  ORDERER_ADDRESS=$2
  
  ORDERER_TLS_CA="$FABRIC_CFG_PATH/tls/chain.crt"
  setPeerGlobals 1

  FILE=/var/hyperledger/${CHANNEL_NAME}.block
  if [ ! -f "/var/hyperledger/${CHANNEL_NAME}.block" ]; then
    set -x
    peer channel fetch 0 ${CHANNEL_NAME}.block -o ${ORDERER_ADDRESS} -c $CHANNEL_NAME --tls --cafile ${ORDERER_TLS_CA} --clientauth --certfile $ADMIN_TLS_CERTFILE --keyfile $ADMIN_TLS_KEYFILE &> $LOG_FILE
    res=$?
    set +x
    cat $LOG_FILE
    verifyResult $res "Fetching '${CHANNEL_NAME}' channel genesis block failed"

    echo
    echo "======== Fetched genesis block of the channel ${CHANNEL_NAME} ==========="
    echo
  fi

  for ((i=1;i<=$HLF_NODE_COUNT;i++));
  do
     joinChannelWithRetry $i $CHANNEL_NAME
  done
}

function joinChannelWithRetry() {
  PEER=$1
  CHANNEL_NAME=$2

  setPeerGlobals $PEER

  set -x
  peer channel join -b $CHANNEL_NAME.block &> $LOG_FILE
  res=$?
  set +x
  if [ $res -ne 0 -a $COUNTER -lt $MAX_RETRY ]; then
    COUNTER=$(expr $COUNTER + 1)
    echo "peer${PEER} of org ${HLF_ORG_NAME} failed to join the channel, Retry after $DELAY seconds"
    sleep $DELAY
    joinChannelWithRetry $PEER $CHANNEL_NAME
  else
    COUNTER=1
  fi
  verifyResult $res "After $MAX_RETRY attempts, peer${PEER} of org ${HLF_ORG_NAME} has failed to join channel '$CHANNEL_NAME' "
  cat $LOG_FILE
  echo "===================== Peer ${PEER} successfully joined channel ${CHANNEL_NAME} ===================== "
  echo
}

function updateAnchorPeer() {
  ANCHOR_PEER_LIST=$1
  CHANNEL_NAME=$2
  ORDERER_ADDRESS=$3

  ORDERER_TLS_CA="$FABRIC_CFG_PATH/tls/chain.crt"
  setPeerGlobals 1
  echo
  echo "========= Creating config transaction to update anchor peer for '${HLF_ORG_NAME}' for channel '${CHANNEL_NAME}' =========== "
  echo
  # Fetch the config for the channel, writing it to config.json
  fetchChannelConfig ${CHANNEL_NAME} config.json

  prepareAnchorPeerJson $ANCHOR_PEER_LIST 
 
  # Modify the configuration to append the new org
  jq -s ".[0] * {\"channel_group\":{\"groups\":{\"Application\":{\"groups\": {\"${HLF_ORG_NAME}\":{\"values\":{\"AnchorPeers\":.[1]}}}}}}}" config.json anchorPeer.json > modified_config.json
  res=$?
  verifyResult $res "Failed to generate new configuration block"

  echo
  echo "========= Compute config update based on difference between current and new configuration =========== "
  echo
  # Compute a config update, based on the differences between config.json and modified_config.json, write it as a transaction to org3_update_in_envelope.pb
  createConfigUpdate ${CHANNEL_NAME} config.json modified_config.json ${HLF_ORG_NAME}_update_in_envelope.pb

  echo
  echo "========= Config transaction to update '${HLF_ORG_NAME}' anchor peer created ===== "
  echo
  echo
  echo "========= Submitting transaction from peer admin which signs it as well ========= "
  echo
  set -x
  peer channel update -f ${HLF_ORG_NAME}_update_in_envelope.pb -c ${CHANNEL_NAME} -o ${ORDERER_ADDRESS} --tls --cafile ${ORDERER_TLS_CA} --clientauth --certfile $ADMIN_TLS_CERTFILE --keyfile $ADMIN_TLS_KEYFILE &> $LOG_FILE
  res=$?
  set +x
  cat $LOG_FILE
  verifyResult $res "peer channel update transaction failed"

  echo
  echo "========= Config transaction to update '${HLF_ORG_NAME}' anchor peer for channel '${CHANNEL_NAME}' submitted! =========== "
  echo
}

function prepareAnchorPeerJson() {
  OLDIFS=$IFS
  IFS=, anchorPeers=($1)
  IFS=$OLDIFS
  lastPeerIndex=$((${#anchorPeers[@]} - 1))
  {
  echo '{"mod_policy": "Admins","value": {"anchor_peers": ['
  for (( i=0; i<${#anchorPeers[@]}; i++ ))
  do
  echo '{"host": "'${anchorPeers[$i]}.${HLF_DOMAIN_NAME}'","port": 443'
  if [ $i -eq ${lastPeerIndex} ]; then
       echo '}'
  else
       echo '},'
  fi
  done
  echo ']},"version": "0"}'
  } > ./anchorPeer.json
}

function verifyPeerName() {
  peer=$1
  if [[ ! "$peer" =~ ^peer[1-9]{1,2}$ ]]; then
    echo "Invalid Peer Name!!! Valid format is \"peer<peer#>\""
    exit 1
  fi 
  
  peerNum=$(echo $peer | tr -d -c 0-9)
  if [ $peerNum -gt $HLF_NODE_COUNT ]; then
      echo "Invalid Peer Number!! It has only \"peer1\" to \"Peer${HLF_NODE_COUNT}\" peer nodes..."
      exit 1
  fi
}

function installDemoChaincode() {
  configAsPeer
  PEER=$1
  verifyPeerName $PEER

  peerNum=$(echo $PEER | tr -d -c 0-9)
  setPeerGlobals $peerNum
  set +e
  result=$(peer chaincode list --installed | grep "${CHAINCODE_NAME}")
  set -e
  if [ -z "$result" ]; then
    #This path is w.r.t path set in $GOPATH
    CC_SRC_PATH="chaincode/chaincode_test/go/"
    set -x
    peer chaincode install -n ${CHAINCODE_NAME} -v ${VERSION} -l ${LANGUAGE} -p ${CC_SRC_PATH} &> $LOG_FILE
    res=$?
    set +x
    verifyResult $res "Chaincode installation on peer${PEER} of org ${HLF_ORG_NAME} has failed"
    cat $LOG_FILE
    echo "===================== Chaincode is installed on peer${PEER} of org ${HLF_ORG_NAME} ===================== "
    echo
  else
    echo
    echo "========== Skipping chaincode installation. It is already installed! ========"
    echo
  fi

}

function instantiateDemoChaincode() {
  configAsPeer
  PEER=$1
  CHANNEL_NAME=$2
  ORDERER_ADDRESS=$3
  
  verifyPeerName $PEER
  
  peerNum=$(echo $PEER | tr -d -c 0-9)
  setPeerGlobals $peerNum
  set +e
  result=$(peer chaincode list --instantiated -C $CHANNEL_NAME | grep "${CHAINCODE_NAME}")
  set -e
  if [ -z "$result" ]; then
    ORDERER_TLS_CA="$FABRIC_CFG_PATH/tls/chain.crt"

    set -x
    peer chaincode instantiate -o "${ORDERER_ADDRESS}" --tls --cafile ${ORDERER_TLS_CA} --clientauth --certfile $ADMIN_TLS_CERTFILE --keyfile $ADMIN_TLS_KEYFILE -C "${CHANNEL_NAME}" -n "${CHAINCODE_NAME}" -l ${LANGUAGE} -v ${VERSION} -c '{"Args":["init","a","1000","b","2000"]}' &> $LOG_FILE
    res=$?
    set +x
    verifyResult $res "Chaincode instantiation on peer${PEER} of org ${HLF_ORG_NAME} on channel '$CHANNEL_NAME' failed"
    cat $LOG_FILE
    echo
    echo "===================== Chaincode is instantiated on peer${PEER} of org ${HLF_ORG_NAME} on channel '$CHANNEL_NAME' ===================== "
    echo

  else
    echo "======== Skipping chaincode instantiation. It is already instantiated! ================"
  fi
}

function invokeDemoChaincode() {
  configAsPeer
  PEER=$1
  CHANNEL_NAME=$2
  ORDERER_ADDRESS=$3

  verifyPeerName $PEER
  peerNum=$(echo $PEER | tr -d -c 0-9)

  #Download orderer TLS from storage account to local directory
  ORDERER_TLS_CA="$FABRIC_CFG_PATH/tls/chain.crt"
  CHAINCODE_NAME="mycc"

  set -x
  peer chaincode invoke -o ${ORDERER_ADDRESS} --tls --cafile $ORDERER_TLS_CA --clientauth --certfile $ADMIN_TLS_CERTFILE --keyfile $ADMIN_TLS_KEYFILE -C $CHANNEL_NAME -n ${CHAINCODE_NAME} -c '{"Args":["invoke","a","b","10"]}' &> $LOG_FILE
  res=$?
  set +x
  verifyResult $res "Invoke execution on $PEER failed "
  cat $LOG_FILE
  echo
  echo "===================== Invoke transaction successful on 'peer$PEER' of org '${HLF_ORG_NAME}' on channel '$CHANNEL_NAME' ===================== "
  echo

}

function queryDemoChaincode() {
  configAsPeer
  PEER=$1
  CHANNEL_NAME=$2

  verifyPeerName $PEER
  peerNum=$(echo $PEER | tr -d -c 0-9)

  TIMEOUT=10
  setPeerGlobals $peerNum
  
  echo "===================== Querying on 'peer${PEER}' of org '${HLF_ORG_NAME}' on channel '$CHANNEL_NAME'... ===================== "

  set -x
  peer chaincode query -C $CHANNEL_NAME -n mycc -c '{"Args":["query","a"]}' >&$LOG_FILE
  res=$?
  set +x
  verifyResult $res "Query result on 'peer${PEER}' of '${HLF_ORG_NAME}' org is INVALID"
  cat $LOG_FILE
  echo
  echo "===================== Query successful on 'peer${PEER}' of '${HLF_ORG_NAME}' org on channel '$CHANNEL_NAME' ===================== "
  VALUE=$(cat $LOG_FILE | egrep '^[0-9]+$')
  echo
  echo "========= RESULT: ${VALUE} =========="
  echo

}
