#!/bin/bash

set -e
set -x

sudo_command="$1"

release=$(. /etc/lsb-release; echo "${DISTRIB_RELEASE//.}")

arch=$(uname -m | sed -e s/aarch64/arm64/)

$sudo_command apt-get update -qq
$sudo_command apt-get install -qq software-properties-common
wget -nv https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$release/$arch/cuda-ubuntu$release.pin
$sudo_command mv cuda-ubuntu$release.pin /etc/apt/preferences.d/cuda-repository-pin-600

# Just fetch all the keys, since they seem to reuse these between distributions.
$sudo_command apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/3bf863cc.pub
$sudo_command apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/7fa2af80.pub

$sudo_command add-apt-repository "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu$release/$arch/ /"
$sudo_command apt-get update -qq
if [[ $release = 1804 ]]; then
    $sudo_command apt-get install -qq cuda-compiler-12.2
elif [[ $release = 2004 ]]; then
    $sudo_command apt-get install -qq cuda-compiler-12.1
else
    echo "Don't know how to install CUDA for this distro"
    lsb_release -a
    exit 1
fi
