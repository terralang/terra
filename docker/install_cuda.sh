#!/bin/bash

set -e
set -x

sudo_command="$1"

release=$(. /etc/lsb-release; echo "${DISTRIB_RELEASE//.}")

arch=$(uname -m | sed -e s/aarch64/sbsa/)

wget -nv https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$release/$arch/cuda-keyring_1.1-1_all.deb
$sudo_command dpkg -i cuda-keyring_1.1-1_all.deb
$sudo_command apt-get update -qq
$sudo_command apt-get install -qq cuda-compiler-12.9
