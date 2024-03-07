#!/bin/bash

escapedPassword=admin
GF_ADMIN_USER=gfpassword
HOST=localhost:3000

DASHBOARDS="./dashboards"
for dashboard in "${DASHBOARDS}/cluster.json" "${DASHBOARDS}/devices.json" "${DASHBOARDS}/nodes.json" "${DASHBOARDS}/lvols.json"; do
    echo -e "\nUploading dashboard: ${dashboard}"
    curl -X POST -H "Content-Type: application/json" \
        -d "@${dashboard}" \
        "http://${GF_ADMIN_USER}:${escapedPassword}@${HOST}/api/dashboards/import"
    echo ""
done

echo "Cluster deployment complete."
