#!/usr/bin/env bash
SCRIPT_PATH=`dirname "$0"`
SCRIPT_PATH="`( cd \"$SCRIPT_PATH\" && pwd )`"
MODELS_PATH=`(echo "$SCRIPT_PATH/../models")`
pushd "$MODELS_PATH"
grpc_tools_ruby_protoc --ruby_out=. \
--grpc_out=. \
./common.proto \
./config.proto \
./context.proto \
./disk.proto \
./network.proto \
./stemcell.proto \
./vm.proto \
./azure_cloud.proto \
./cpi_service.proto
popd