#!/bin/bash

set -e

IFS=- read distro release <<< "$1"
llvm="$2"
variant="$3"

docker build --build-arg release=$release --build-arg llvm=$llvm -t terralang/terra:$distro-$release -f docker/Dockerfile.$distro${variant:+-}$variant .

# Copy files out of container and make release.
tmp=$(docker create terralang/terra:${distro}-${build_version})
docker cp $tmp:/terra_install .
docker rm $tmp

RELEASE_NAME=terra-$distro$release-llvm$llvm-`uname -m`-`git rev-parse --short HEAD`
mv terra_install $RELEASE_NAME
zip -q -r $RELEASE_NAME.zip $RELEASE_NAME
mv $RELEASE_NAME terra_install
