#!/usr/bin/env bash

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

INSTALL_CUDNN=${INSTALLCUDNN}
INSTALL_CUDNNDEV=${INSTALLCUDNNDEV}
INSTALL_TRT=${INSTALLTRT}
INSTALL_TRTDEV=${INSTALLTRTDEV}
INSTALL_NVTX=${INSTALLNVTX}
INSTALL_TOOLKIT=${INSTALLTOOLKIT}
CUDA_VERSION=${CUDAVERSION}
CUDNN_VERSION=${CUDNNVERSION}
TRT_VERSION=${TRTVERSION}

. /etc/os-release 

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

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

if [ $VERSION_CODENAME = "bookworm" ] || [ $VERSION_CODENAME = "jammy" ] && [ $CUDA_VERSION \< 11.7 ]; then  
    echo "(!) Unsupported distribution version '${VERSION_CODENAME}' for CUDA < 11.7"
    exit 1
fi  

export DEBIAN_FRONTEND=noninteractive

check_packages wget ca-certificates

# Determine system architecture and set NVIDIA repository URL accordingly
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        NVIDIA_ARCH="x86_64"
        ;;
    aarch64 | arm64)
        NVIDIA_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Add NVIDIA's package repository to apt so that we can download packages

declare -A os_codes=(
    ["bookworm"]="debian12"
    ["trixie"]="debian13"
    ["jammy"]="ubuntu2204"
    ["noble"]="ubuntu2404"
    ["resolute"]="ubuntu2604"
)

NVIDIA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/${os_codes[$VERSION_CODENAME]}/$NVIDIA_ARCH"

KEYRING_PACKAGE="cuda-keyring_1.1-1_all.deb"
KEYRING_PACKAGE_URL="$NVIDIA_REPO_URL/$KEYRING_PACKAGE"
KEYRING_PACKAGE_PATH="$(mktemp -d)"
KEYRING_PACKAGE_FILE="$KEYRING_PACKAGE_PATH/$KEYRING_PACKAGE"
wget -O "$KEYRING_PACKAGE_FILE" "$KEYRING_PACKAGE_URL"
apt-get install -yq "$KEYRING_PACKAGE_FILE"
apt-get update -yq

# Ensure that the requested version of CUDA is available
cuda_pkg="cuda-libraries-${CUDA_VERSION/./-}"
nvtx_pkg="cuda-nvtx-${CUDA_VERSION/./-}"
toolkit_pkg="cuda-toolkit-${CUDA_VERSION/./-}"
if ! apt-cache show "$cuda_pkg"; then
    echo "The requested version of CUDA is not available: CUDA $CUDA_VERSION"
    if [ "$NVIDIA_ARCH" = "arm64" ]; then
        echo "Note: arm64 supports limited CUDA versions. Please check available versions:"
        echo "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64"
    fi
    exit 1
fi

echo "Installing CUDA libraries..."
apt-get install -yq "$cuda_pkg"
apt-get update -yq --fix-missing

# auto find recent cudnn version
major_cuda_version=$(echo "${CUDA_VERSION}" | cut -d '.' -f 1)
if [ "$CUDNN_VERSION" = "automatic" ]; then
    if [[ "$CUDA_VERSION" < "12.3" ]]; then
        CUDNN_VERSION=$(apt-cache policy libcudnn8 | grep "$CUDA_VERSION" | grep -Eo '^[^-1+]*' | sort -V | tail -n1 | xargs)
    else
        CUDNN_VERSION=$(apt-cache policy libcudnn9-cuda-$major_cuda_version | grep "Candidate" | awk '{print $2}' | grep -Eo '^[^-+]*')
    fi
fi
major_cudnn_version=$(echo "${CUDNN_VERSION}" | cut -d '.' -f 1)

if [ "$INSTALL_CUDNN" = "true" ]; then
    # Ensure that the requested version of cuDNN is available AND compatible
    #if major cudnn version is 9, then we need to install libcudnn9-cuda-<major_cuda_version>_<CUDNN_VERSION>-1 package
    #else we need to install libcudnn8_<CUDNN_VERSION>-1+cuda<CUDA_VERSION>" package
    if [[ $major_cudnn_version -ge "9" ]]
    then
        cudnn_pkg_version="libcudnn9-cuda-${major_cuda_version}=${CUDNN_VERSION}-1"
    else
        cudnn_pkg_version="libcudnn8=${CUDNN_VERSION}-1+cuda${CUDA_VERSION}"
    fi

    if ! apt-cache show "$cudnn_pkg_version"; then
        echo "The requested version of cuDNN is not available: cuDNN $CUDNN_VERSION for CUDA $CUDA_VERSION"
        if [ "$NVIDIA_ARCH" = "arm64" ]; then
            echo "Note: arm64 has limited cuDNN package availability"
        fi
        exit 1
    fi

    echo "Installing cuDNN libraries..."
    apt-get install -yq "$cudnn_pkg_version"
fi

if [ "$INSTALL_CUDNNDEV" = "true" ]; then
    # Ensure that the requested version of cuDNN development package is available AND compatible
    #if major cudnn version is 9, then we need to install libcudnn9-dev-cuda-<major_cuda_version>_<CUDNN_VERSION>-1 package
    #else we need to install libcudnn8-dev_<CUDNN_VERSION>-1+cuda<CUDA_VERSION>" package
    if [[ $major_cudnn_version -ge "9" ]]
    then
        cudnn_dev_pkg_version="libcudnn9-dev-cuda-${major_cuda_version}=${CUDNN_VERSION}-1"
    else
        cudnn_dev_pkg_version="libcudnn8-dev=${CUDNN_VERSION}-1+cuda${CUDA_VERSION}"
    fi
    if ! apt-cache show "$cudnn_dev_pkg_version"; then
        echo "The requested version of cuDNN development package is not available: cuDNN $CUDNN_VERSION for CUDA $CUDA_VERSION"
        if [ "$NVIDIA_ARCH" = "arm64" ]; then
            echo "Note: arm64 has limited cuDNN development package availability"
        fi
        exit 1
    fi

    echo "Installing cuDNN dev libraries..."
    apt-get install -yq "$cudnn_dev_pkg_version"
fi

# auto find recent TensorRT version
major_trt_version=$(echo "${TRT_VERSION}" | cut -d '.' -f 1)
if [ "$TRT_VERSION" = "automatic" ]; then
    
    if [[ "$CUDA_VERSION" < "12.9" ]]; then
        trt_related_version=$(apt-cache policy libnvinfer10 | grep -E "[[:graph:]]+\+cuda[[:graph:]]+[[:blank:]]" | awk '{print $1}')
    else
        trt_related_version=$(apt-cache policy libnvinfer11 | grep -E "[[:graph:]]+\+cuda[[:graph:]]+[[:blank:]]" | awk '{print $1}')
    fi
else
    trt_related_version="${TRT_VERSION}-1+cuda${CUDA_VERSION}"
fi

if [ "$INSTALL_TRT" = "true" ]; then
    # Ensure that the requested version of TensorRT is available AND compatible
    if ! apt-cache show "libnvinfer-bin=$trt_related_version"; then
        echo "The requested version of TensorRT is not available: TensorRT $TRT_VERSION for CUDA $CUDA_VERSION"
        exit 1
    fi

    echo "Installing TensorRT libraries..."

    apt-get install -yq \
        libnvinfer-bin=${version} \
        libnvinfer-dispatch${major_trt_version}=${version} \
        libnvinfer-lean${major_trt_version}=${version} \
        libnvinfer-plugin${major_trt_version}=${version} \
        libnvinfer-vc-plugin${major_trt_version}=${version} \
        libnvinfer-win-builder-resource${major_trt_version}=${version} \
        libnvinfer11=${version} \
        libnvonnxparsers${major_trt_version}=${version} \
        python3-libnvinfer-dispatch=${version} \
        python3-libnvinfer-lean=${version} \
        python3-libnvinfer=${version} \
        tensorrt-libs=${version} \
        tensorrt=${version}
fi

if [ "$INSTALL_TRTDEV" = "true" ]; then
    # Ensure that the requested version of TensorRT development package is available AND compatible
    if ! apt-cache show "libnvinfer-dev=$trt_related_version"; then
        echo "The requested version of TensorRT development libraries is not available: TensorRT $TRT_VERSION for CUDA $CUDA_VERSION"
        exit 1
    fi

    echo "Installing TensorRT development libraries..."

    apt-get install -yq \
        libnvinfer-dev=${version} \
        libnvinfer-dispatch-dev=${version} \
        libnvinfer-headers-dev=${version} \
        libnvinfer-headers-plugin-dev=${version} \
        libnvinfer-headers-python-plugin-dev=${version} \
        libnvinfer-lean-dev=${version} \
        libnvinfer-plugin-dev=${version} \
        libnvinfer-safe-headers-dev=${version} \
        libnvinfer-vc-plugin-dev=${version} \
        libnvonnxparsers-dev=${version} \
        python3-libnvinfer-dev=${version} \
        tensorrt-dev=${version}
fi

if [ "$INSTALL_NVTX" = "true" ]; then
    echo "Installing NVTX..."
    apt-get install -yq "$nvtx_pkg"
fi

if [ "$INSTALL_TOOLKIT" = "true" ]; then
    echo "Installing CUDA Toolkit..."
    apt-get install -yq "$toolkit_pkg"
fi

# Clean up
rm -rf /var/lib/apt/lists/*

echo "Done!"