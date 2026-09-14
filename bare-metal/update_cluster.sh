#!/usr/bin/env bash

# to update on dev: sudo ./cluster_update.sh --sbcli-cmd sbcli-dev --image-tag dev
# to update on prod: sudo ./cluster_update.sh --sbcli-cmd sbcli-release --image-tag release_v1

SBCLI_CMD="sbcli-dev"
IMAGE_TAG="release_v1"

# sbcli requires python >= 3.11, which the nodes don't ship, so it is installed
# as a uv tool against a uv-managed interpreter. Both uv and the sbcli entry
# point go to /usr/local/bin, which is on sudo's secure_path.
UV_INSTALL_DIR="${UV_INSTALL_DIR:-/usr/local/bin}"
UV_BIN="${UV_INSTALL_DIR}/uv"
SBCLI_PYTHON_VERSION="${SBCLI_PYTHON_VERSION:-3.11}"

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
    --sbcli-cmd)
        SBCLI_CMD="$2"
        shift
        ;;
    --image-tag)
        IMAGE_TAG="$2"
        shift
        ;;
    *)
        echo "Unknown option: $1"
        print_help
        ;;
    esac
    shift
done

get_service_ids() {
    docker service ls | grep simplyblock/simplyblock | awk '{print $1}'
}

if [ ! -x "${UV_BIN}" ]; then
    curl -LsSf https://astral.sh/uv/install.sh \
        | env UV_INSTALL_DIR="${UV_INSTALL_DIR}" INSTALLER_NO_MODIFY_PATH=1 sh
fi

UV_TOOL_BIN_DIR="${UV_INSTALL_DIR}" "${UV_BIN}" tool install --force \
    --python "${SBCLI_PYTHON_VERSION}" "${SBCLI_CMD}"

docker image pull simplyblock/simplyblock:${IMAGE_TAG}
service_ids=$(get_service_ids)
for service_id in ${service_ids}; do
    docker service update "$service_id" --image simplyblock/simplyblock:${IMAGE_TAG} --force
done
