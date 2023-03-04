#!/bin/sh

export IMAGE="registry.k8s.io/autoscaling/cluster-autoscaler"
export TAG="v1.26.1"
export SRC_FILE="cluster-autoscaler"
export DST_FILE="$SRC_FILE-$TAG-linux-amd64"

./extract-from-container-image.sh "$IMAGE" "$TAG" "$SRC_FILE" "$DST_FILE"
