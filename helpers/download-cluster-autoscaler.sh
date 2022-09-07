#!/bin/sh

export IMAGE="k8s.gcr.io/autoscaling/cluster-autoscaler"
export TAG="v1.25.0"
export SRC_FILE="cluster-autoscaler"
export DST_FILE="$SRC_FILE-$TAG-linux-amd64"

./extract-from-container-image.sh "$IMAGE" "$TAG" "$SRC_FILE" "$DST_FILE"
