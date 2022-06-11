#!/bin/bash

set -e

distro="$1"
build_version="$2"
test_versions="$3"
arch="$4"
llvm="$5"
variant="$6"
threads="$7"

./docker/build.sh "${distro}-${build_version}" "$arch" "$llvm" "$variant" "$threads"

cd terra_install

for version in $test_versions; do
    docker build --build-arg release=$version -t terralang/terra:$distro-$version-test -f ../docker/Dockerfile.$distro${variant:+-}$variant-test .
    docker rmi terralang/terra:$distro-$version-test
done
