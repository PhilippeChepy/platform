#!/bin/sh

docker run -it --rm --platform linux/amd64 -v ${PWD}:/host -w /host --entrypoint /host/.helpers/init.sh ubuntu:focal

