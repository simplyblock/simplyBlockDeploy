#!/usr/bin/env bash

# to update on dev: sudo ./cluster_update.sh --sbcli-cmd sbcli-dev --image-tag dev
# to update on prod: sudo ./cluster_update.sh --sbcli-cmd sbcli-release --image-tag release_v1

SBCLI_CMD="sbcli-dev"
IMAGE_TAG="release_v1"

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
    docker service ls | grep public.ecr.aws/simply-block/simplyblock | awk '{print $1}'
}

pip install ${SBCLI_CMD} --upgrade
docker image pull simplyblock/simplyblock:${IMAGE_TAG}
service_ids=$(get_service_ids)
for service_id in ${service_ids}; do
    docker service update "$service_id" --image public.ecr.aws/simply-block/simplyblock:${IMAGE_TAG} --force
done
