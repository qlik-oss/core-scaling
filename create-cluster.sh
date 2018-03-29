#!/bin/bash -v

cd "$(dirname "$0")"
set -e

source settings.config

gcloud container --project $GCLOUD_PROJECT clusters create $K8S_CLUSTER \
  --zone $GCLOUD_ZONE --username="admin" --cluster-version $K8S_VERSION \
  --machine-type $GCLOUD_MACHINE_TYPE --image-type $GCLOUD_IMAGE_TYPE \
  --disk-size $GCLOUD_DISK_SIZE --scopes $GCLOUD_SCOPES --num-nodes $GCLOUD_NUM_NODES \
  --network "default" --enable-cloud-logging --enable-cloud-monitoring \
  --subnetwork "default" --enable-autoscaling --min-nodes $GCLOUD_MIN_NODES \
  --max-nodes $GCLOUD_MAX_NODES --addons KubernetesDashboard &&
gcloud compute disks create --size=10GB --zone=$GCLOUD_ZONE app-nfs-disk
