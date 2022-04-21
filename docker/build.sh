#!/bin/bash

set -e

IFS=- read distro release <<< "$1"
llvm="$2"
variant="$3"
threads="$4"

docker build --build-arg release=$release --build-arg llvm=$llvm --build-arg threads=${threads:-4} -t terralang/terra:$distro-$release -f docker/Dockerfile.$distro${variant:+-}$variant .

# Copy files out of container and make release.
tmp=$(docker create terralang/terra:$distro-$release)
docker cp $tmp:/terra_install .
docker rm $tmp

if command -v zip; then
    RELEASE_NAME=terra-`uname | sed -e s/Darwin/OSX/`-`uname -m`-`git rev-parse --short HEAD`
    mv terra_install $RELEASE_NAME
    tar cfJv $RELEASE_NAME.tar.xz $RELEASE_NAME
    mv $RELEASE_NAME terra_install
else
    echo "The zip program is not available. Can't make a release."
fi
