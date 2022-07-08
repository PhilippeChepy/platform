#!/bin/sh

export IMAGE="eu.gcr.io/k8s-artifacts-prod/kas-network-proxy/proxy-server"
export TAG="v0.0.32"
export SRC_FILE="proxy-server"
export DST_FILE="$SRC_FILE-$TAG-linux-amd64"

./extract-from-container-image.sh "$IMAGE" "$TAG" "$SRC_FILE" "$DST_FILE"
