#!/usr/bin/env bash

cd "$(dirname "$0")"
set -e

POD=$(kubectl get pods --selector="role=nfs-server" -o=jsonpath='{.items[0].metadata.name}')

# NOTE: Using the // format on file paths is to make it work in Git Bash on Windows which otherwise converts such
#       paths to Windows paths.
kubectl cp ./doc/Shared-Africa-Urbanization.qvf $POD://exports
