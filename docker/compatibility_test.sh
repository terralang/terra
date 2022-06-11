#!/bin/bash

set -e

distro="$1"
build_version="$2"
test_versions="$3"
arch="$5"
llvm="$6"
variant="$7"
threads="$8"

set -x

./docker/build.sh "${distro}-${build_version}" "$arch" "$llvm" "$variant" "$threads"

cd terra_install

for version in $test_versions; do
    docker build --build-arg release=$version -t terralang/terra:$distro-$version-test -f ../docker/Dockerfile.$distro${variant:+-}$variant-test .
    docker rmi terralang/terra:$distro-$version-test
done
