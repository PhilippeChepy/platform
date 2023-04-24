#!/bin/sh

export IMAGE="registry.k8s.io/kas-network-proxy/proxy-server"
export TAG="v0.1.2"
export SRC_FILE="proxy-server"
export DST_FILE="$SRC_FILE-$TAG-linux-amd64"

./extract-from-container-image.sh "$IMAGE" "$TAG" "$SRC_FILE" "$DST_FILE"
