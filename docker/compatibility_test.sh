#!/bin/bash

set -e

distro="$1"
build_version="$2"
test_versions="$3"
arch="$4"
llvm="$5"
lua="$6"
cuda=1
variant="$7"
test=1
threads="$8"

./docker/build.sh "${distro}-${build_version}" "$arch" "$llvm" "$cuda" "$variant" "$test" "$threads"

cd terra_install

for version in $test_versions; do
    docker build --build-arg release=$version -t terralang/terra:$distro-$version-test -f ../docker/Dockerfile.$distro${variant:+-}$variant-test .
    docker rmi terralang/terra:$distro-$version-test
done
