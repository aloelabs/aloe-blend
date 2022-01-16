#!/usr/bin/env bash

set -eo pipefail

contract_creationCode() {
	NAME=$1
	ARGS=${@:2}
	# select the filename and the contract in it
	PATTERN=".contracts[\"contracts/$NAME.sol\"].$NAME"

	# get the bytecode from the compiled file
	BYTECODE=$(jq -r "$PATTERN.evm.bytecode.object" build_dapp/dapp.sol.json)
	echo "$BYTECODE"
}

contract_size() {
	NAME=$1
	ARGS=${@:2}
	# select the filename and the contract in it
	PATTERN=".contracts[\"contracts/$NAME.sol\"].$NAME"

	# get the bytecode from the compiled file
	BYTECODE=$(jq -r "$PATTERN.evm.bytecode.object" build_dapp/dapp.sol.json)
	length=$(echo "$BYTECODE" | wc -m)
	echo $(($length / 2))
}

if [[ -z $contract ]]; then
  if [[ -z ${1} ]];then
    echo '"$contract" env variable is not set. Set it to the name of the contract you want to estimate size for.'
    exit 1
  else
    contract=${1}
  fi
fi

dapp build

echo $(contract_creationCode ${contract})

contract_size=$(contract_size ${contract})
echo "Contract Name: ${contract}"
echo "Contract Size: ${contract_size} bytes"
echo
echo "$(( 24576 - ${contract_size} )) bytes left to reach the smart contract size limit of 24576 bytes."
