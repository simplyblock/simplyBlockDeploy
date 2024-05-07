#!/usr/bin/env bash

get_service_ids() {
  docker service ls | grep simplyblock/simplyblock | awk '{print $1}'
}

pip install sbcli-release --upgrade
docker image pull simplyblock/simplyblock:release_v1
service_ids=$(get_service_ids)
for service_id in ${service_ids}; do
  docker service update "$service_id" --image simplyblock/simplyblock:release_v1 --force
done
