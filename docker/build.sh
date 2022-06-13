#!/bin/bash

set -e

IFS=- read distro release <<< "$1"
arch="$2"
llvm="$3"
variant="$4"
threads="$5"

if [[ -n $arch ]]; then
    export DOCKER_BUILDKIT=1
fi

arch_long=$(echo $arch | sed -e s/arm64/aarch64/ | sed -e s/ppc64le/powerpc64le/)

docker build ${arch:+--platform=}$arch --build-arg release=$release ${arch:+--build-arg arch=}$arch_long --build-arg llvm=$llvm --build-arg threads=${threads:-4} -t terralang/terra:$distro-$release -f docker/Dockerfile.$distro${variant:+-}$variant .

# Copy files out of container and make release.
tmp=$(docker create terralang/terra:$distro-$release)
docker cp $tmp:/terra_install .
docker rm $tmp

arch_release=$(echo $arch | sed -e s/arm64/aarch64/)

RELEASE_NAME=terra-`uname | sed -e s/Darwin/OSX/`-${arch_release:-$(uname -m)}-`git rev-parse --short HEAD`
mv terra_install $RELEASE_NAME
tar cfJv $RELEASE_NAME.tar.xz $RELEASE_NAME
mv $RELEASE_NAME terra_install
