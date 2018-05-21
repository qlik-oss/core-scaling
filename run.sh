#!/bin/bash

set -e

# move into project root:
cd "$(dirname "$0")"

# set settings values
source settings.config

command=$1

function create_cluster() {
  gcloud container --project $GCLOUD_PROJECT clusters create $K8S_CLUSTER \
  --zone $GCLOUD_ZONE --username="admin" --cluster-version $K8S_VERSION \
  --machine-type $GCLOUD_MACHINE_TYPE --image-type $GCLOUD_IMAGE_TYPE \
  --disk-size $GCLOUD_DISK_SIZE --scopes $GCLOUD_SCOPES --num-nodes $GCLOUD_NUM_NODES \
  --network "default" --enable-cloud-logging --enable-cloud-monitoring \
  --subnetwork "default" --enable-autoscaling --min-nodes $GCLOUD_MIN_NODES \
  --max-nodes $GCLOUD_MAX_NODES &&
gcloud compute disks create --size=10GB --zone=$GCLOUD_ZONE app-nfs-disk &&
gcloud container node-pools create monitoring --cluster=$K8S_CLUSTER \
  --machine-type=$GCLOUD_MACHINE_TYPE --num-nodes=1
}

function deploy_enviroment() {
  kubectl create -f ./namespaces.yaml
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value core/account)
  kubectl create -f ./prometheus
  kubectl create -f ./custom-metrics-api
  kubectl create -f ./ingress
  kubectl create -f ./nfs-volumes
  kubectl create -f ./grafana
}

function doc_seed() {
  POD=$(kubectl get pods --selector="role=nfs-server" -o=jsonpath='{.items[0].metadata.name}')
  # NOTE: Using the // format on file paths is to make it work in Git Bash on Windows which otherwise converts such
  #       paths to Windows paths.
  kubectl cp ./doc/happiness.qvf $POD://exports
}

function deploy_core() {
  kubectl create -f ./rbac-config.yaml
  kubectl create -f ./qlik-core
}

function port_forward_grafana() {
  kubectl port-forward --namespace=monitoring $(kubectl get pods --namespace=monitoring --selector="app=grafana" -o=jsonpath='{.items[0].metadata.name}') 3000:3000
}

function remove_cluster() {
  gcloud container -q clusters delete $K8S_CLUSTER &&
  gcloud compute -q disks delete app-nfs-disk
}

function get_external_ip() {
  kubectl get service ingress-nginx --namespace ingress-nginx
}

function deploy_all() {
  create_cluster
  deploy_enviroment

  echo "Waiting for deployment to run"
  sleep 45

  doc_seed
  deploy_core

  echo "Waiting for Grafana"
  sleep 20

  get_external_ip
  port_forward_grafana
}

if [ "$command" == "deploy" ]; then deploy_all
if [ "$command" == "create" ]; then create_cluster
if [ "$command" == "docs" ]; then doc_seed
elif [ "$command" == "remove" ]; then remove_cluster
elif [ "$command" == "ip" ]; then get_external_ip
elif [ "$command" == "grafana" ]; then port_forward_grafana
else echo "Invalid option: $command - please use one of: deploy, remove, ip, grafana"; fi
