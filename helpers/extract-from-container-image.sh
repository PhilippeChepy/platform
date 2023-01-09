#!/bin/sh

export IMAGE="$1"
export TAG="$2"
export SRC_FILE="$3"
export DST_FILE="$4"

export TMP_DIR="${DST_FILE}.tmp"

image_download() {
    echo " > Downloading container image"
    mkdir -p "${TMP_DIR}"
    docker pull --platform linux/amd64 "$IMAGE:$TAG" > /dev/null
    docker save "$IMAGE:$TAG" > "${TMP_DIR}/image.tar"
}

image_extract() {
    mkdir -p "${TMP_DIR}/image.layers"
    mkdir -p "${TMP_DIR}/image.extracted"
    echo " > Extracting container image"
    tar xf "${TMP_DIR}/image.tar" -C "${TMP_DIR}/image.layers"
    
    for layer in "${TMP_DIR}/image.layers/"*/ ; do
        echo " > Extracting layer ${layer}"
        tar xf "${layer}/layer.tar" -C "${TMP_DIR}/image.extracted"
    done

    echo " > Grabbing file: ${SRC_FILE} -> ${DST_FILE}"
    mv "${TMP_DIR}/image.extracted/${SRC_FILE}" "${DST_FILE}"
}

cleanup() {
    echo " > Cleaning up"
    rm -rf "${TMP_DIR}"
}

cleanup
image_download
image_extract
cleanup