#!/bin/bash

set -e

IFS=- read distro release <<< "$1"
arch="$2"
llvm="$3"
lua="$4"
cuda="$5"
variant="$6"
test="$7"
threads="$8"

if [[ -n $arch ]]; then
    export DOCKER_BUILDKIT=1
fi

docker build ${arch:+--platform=}$arch --build-arg release=$release --build-arg llvm=$llvm --build-arg lua=$lua --build-arg cuda=$cuda --build-arg variant=$variant --build-arg test=$test --build-arg threads=${threads:-4} -t terralang/terra:$distro-$release -f docker/Dockerfile.$distro .

# Copy files out of container and make release.
tmp=$(docker create terralang/terra:$distro-$release)
docker cp $tmp:/terra_install .
docker rm $tmp

arch_release=$(echo $arch | sed -e s/arm64/aarch64/)

RELEASE_NAME=terra-`uname | sed -e s/Darwin/OSX/`-${arch_release:-$(uname -m)}-`git rev-parse --short HEAD`
mv terra_install $RELEASE_NAME
tar cfJv $RELEASE_NAME.tar.xz $RELEASE_NAME
mv $RELEASE_NAME terra_install
