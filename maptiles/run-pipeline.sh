#!/bin/bash
#
# run-pipeline.sh starts stats-pipeline for the current year and then
# generates updated maptiles.

set -euxo pipefail
PROJECT=${PROJECT:?Please provide project}

# Start stats-pipeline for the current year
year=$(date +%Y)

if ! curl -X POST "http://stats-pipeline-service:8080/v0/pipeline?year=${year}"; then
    echo "Stats-pipeline failed, please check the container logs."
    exit 1
fi

echo "Stats-pipeline completed successfully"
#export GCS_BUCKET=maptiles-${PROJECT}
#make piecewise
