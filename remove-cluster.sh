#!/bin/bash -v

cd "$(dirname "$0")"
set -e

source settings.config

gcloud container -q clusters delete $K8S_CLUSTER &&
gcloud compute -q disks delete app-nfs-disk
