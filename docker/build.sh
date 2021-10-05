#!/bin/bash

set -e

IFS=- read distro release <<< "$1"
llvm="$2"

docker build --build-arg release=$release --build-arg llvm=$llvm -t terralang/terra:$distro-$release -f docker/Dockerfile.$distro .
