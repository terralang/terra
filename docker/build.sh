#!/bin/bash

set -e

IFS=- read distro release <<< "$1"

docker build --build-arg release=$release -t terralang/terra:$distro-$release -f docker/Dockerfile.$distro .
