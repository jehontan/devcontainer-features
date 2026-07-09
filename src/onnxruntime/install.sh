#!/usr/bin/env bash

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

INSTALL_GPU=${INSTALLGPU}
INSTALL_CXX=${INSTALLCXX}
ORT_VERSION=${ORTVERSION}

apt_get_update()
{
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
    fi
}

check_packages python3-pip jq

ORT_PACKAGE_PATH="$(mktemp -d)"

if [ "$INSTALL_GPU" = "true" ]; then
    # check if CUDA installed
    if [ "$(find /usr/local/cuda/ -name version.json | wc -l)" -eq "0" ]; then
        # CUDA not installed
        echo "(!) onnxruntime-gpu install requires CUDA!"
        exit 1
    fi

    echo "Installing onnxruntime-gpu"

    CUDA_VERSION=$(cat /usr/local/cuda/version.json | jq -r '.cuda.version')
    major_cuda_version=$(echo "${CUDA_VERSION}" | cut -d '.' -f 1)

    # CUDA 11 needs to be handled differently
    if [ $major_cuda_version = "11" ]; then
        pip install coloredlogs flatbuffers numpy packaging protobuf sympy
        pip install onnxruntime-gpu --index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/onnxruntime-cuda-11/pypi/simple/
    
        ORT_PACKAGE_NAME="onnxruntime-linux-x64-gpu-${ORT_VERSION}"
    else
        pip install onnxruntime-gpu
        
        # CUDA 13 has different naming convention
        if [ $major_cuda_version = "13" ]; then
            ORT_PACKAGE_NAME="onnxruntime-linux-x64-gpu_cuda13-${ORT_VERSION}"
        else 
            ORT_PACKAGE_NAME="onnxruntime-linux-x64-gpu-${ORT_VERSION}"
        fi
    fi

    if [ "$INSTALL_CXX" = "true" ]; then
        echo "Installing Cxx libraries with GPU support..."
        ORT_PACKAGE_FILE="$ORT_PACKAGE_PATH/$ORT_PACKAGE_NAME.tgz"
        ORT_PACKAGE_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/${ORT_PACKAGE_NAME}.tgz"
        
        wget -O "$ORT_PACKAGE_FILE" "$ORT_PACKAGE_URL"
        tar -xzf $ORT_PACKAGE_FILE -C /usr/local
    fi

else
    echo "Installing onnxruntime"

    pip install onnxruntime

    ORT_PACKAGE_NAME="onnxruntime-linux-x64-${ORT_VERSION}"

    if [ "$INSTALL_CXX" = "true" ]; then
        echo "Installing Cxx libraries..."
        ORT_PACKAGE_FILE="$ORT_PACKAGE_PATH/$ORT_PACKAGE_NAME.tgz"
        ORT_PACKAGE_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/${ORT_PACKAGE_NAME}.tgz"
        
        wget -O "$ORT_PACKAGE_FILE" "$ORT_PACKAGE_URL"
        tar -xzf $ORT_PACKAGE_FILE -C /usr/local
    fi
fi

ln -s "/usr/local/${ORT_PACKAGE_NAME}" /usr/local/onnxruntime

echo "Done!"