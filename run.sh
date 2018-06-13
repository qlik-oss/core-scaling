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
  --machine-type=$GCLOUD_MACHINE_TYPE --num-nodes=1 --zone $GCLOUD_ZONE
}

function deploy_enviroment() {
  kubectl apply -f ./namespaces.yaml
  kubectl apply -f ./prometheus
  kubectl apply -f ./custom-metrics-api
  kubectl apply -f ./ingress
  kubectl apply -f ./nfs-volumes
  kubectl apply -f ./grafana
}

function create_role_binding() {
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value core/account) --dry-run
}

function doc_seed() {
  POD=$(kubectl get pods --selector="role=nfs-server" -o=jsonpath='{.items[0].metadata.name}')
  # NOTE: Using the // format on file paths is to make it work in Git Bash on Windows which otherwise converts such
  #       paths to Windows paths.
  kubectl cp ./doc/Shared-Africa-Urbanization.qvf $POD://exports
}

function deploy_core() {
  kubectl apply -f ./rbac-config.yaml
  kubectl apply -f ./qlik-core
}

function port_forward_grafana() {
  kubectl port-forward --namespace=monitoring $(kubectl get pods --namespace=monitoring --selector="app=grafana" -o=jsonpath='{.items[0].metadata.name}') 3000:3000
}

function remove_cluster() {
  gcloud container -q clusters delete $K8S_CLUSTER --zone $GCLOUD_ZONE &&
  gcloud compute -q disks delete app-nfs-disk --zone $GCLOUD_ZONE
}

function get_external_ip() {
  kubectl get service ingress-nginx --namespace ingress-nginx
}

function deploy_all() {
  create_cluster
  create_role_binding
  deploy_enviroment

  echo "Waiting for deployment to run"
  sleep 50

  doc_seed
  deploy_core

  echo "Waiting for Grafana"
  sleep 20

  get_external_ip
  port_forward_grafana
}

function update_cluster() {
  create_role_binding
  deploy_enviroment

  echo "Waiting for deployment to run"
  sleep 50

  doc_seed
  deploy_core
}

if [ "$command" == "deploy" ]; then deploy_all
elif [ "$command" == "create" ]; then create_cluster
elif [ "$command" == "update" ]; then update_cluster
elif [ "$command" == "populate-docs" ]; then doc_seed
elif [ "$command" == "remove" ]; then remove_cluster
elif [ "$command" == "ip" ]; then get_external_ip
elif [ "$command" == "grafana" ]; then port_forward_grafana
else echo "Invalid option: $command - please use one of: deploy, create, update, docs, remove, ip, grafana"; fi
