#!/bin/bash

set -e

# move into project root:
cd "$(dirname "$0")"

# set settings values
source settings.config

command=$1

function bootstrap() {
  # create cluster
  gcloud container --project $GCLOUD_PROJECT clusters create $K8S_CLUSTER \
  --zone $GCLOUD_ZONE --no-enable-basic-auth --cluster-version $K8S_VERSION \
  --machine-type $GCLOUD_MACHINE_TYPE --image-type $GCLOUD_IMAGE_TYPE \
  --disk-size $GCLOUD_DISK_SIZE --scopes=$GCLOUD_SCOPES --num-nodes $GCLOUD_NUM_NODES \
  --network "default" --enable-cloud-logging --enable-cloud-monitoring \
  --subnetwork "default" --enable-autoscaling --min-nodes $GCLOUD_MIN_NODES \
  --max-nodes $GCLOUD_MAX_NODES --metadata disable-legacy-endpoints=true \
  --enable-ip-alias --enable-autoupgrade --enable-autorepair --addons HorizontalPodAutoscaling \
  --no-issue-client-certificate

  # create volume
  gcloud compute disks create --project=$GCLOUD_PROJECT --size=10GB --zone=$GCLOUD_ZONE $DISK_NAME

  # create monitoring node pool
  gcloud container node-pools create monitoring --project=$GCLOUD_PROJECT --cluster=$K8S_CLUSTER --scopes=$GCLOUD_SCOPES \
  --machine-type=$GCLOUD_MACHINE_TYPE --num-nodes=1 --zone $GCLOUD_ZONE --metadata disable-legacy-endpoints=true

  # infra configuration
  kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value core/account) --dry-run -o=yaml | kubectl apply -f -
  kubectl apply -f ./helm/rbac-config.yaml
  kubectl apply -f ./helm/namespaces.yaml
  helm init --service-account tiller --upgrade
  kubectl rollout status -w deployment/tiller-deploy --namespace=kube-system
}

function copy_apps() {
  kubectl rollout status -w deployment/nfs-server
  POD=$(kubectl get pods --selector="role=nfs-server" -o=jsonpath='{.items[0].metadata.name}')
  # NOTE: Using the // format on file paths is to make it work in Git Bash on Windows which otherwise converts such
  #       paths to Windows paths.
  kubectl cp ./doc/default $POD://exports
}

function upgrade() {
  # set up licensing info/secret
  kubectl create secret generic license-data --from-literal LICENSES_SERIAL_NBR=$LICENSES_SERIAL_NBR --from-literal LICENSES_CONTROL_NBR=$LICENSES_CONTROL_NBR --dry-run -o=yaml | kubectl apply -f -

  # configuration
  kubectl apply -f ./helm/grafana-datasources-cfg.yaml
  kubectl apply -f ./helm/grafana-dashboards-cfg.yaml

  # infrastructure
  helm upgrade --install prometheus --namespace monitoring stable/prometheus
  helm upgrade --install custom-metrics-apiserver --namespace monitoring stable/prometheus-adapter -f ./helm/values/prom-adapter.yaml
  helm upgrade --install grafana --namespace monitoring stable/grafana -f ./helm/values/grafana.yaml
  helm upgrade --install nginx-ingress stable/nginx-ingress -f ./helm/values/nginx-ingress.yaml
  helm upgrade --install nfs-server ./helm/nfs --set persistence.diskName=$DISK_NAME

  # copy over apps
  copy_apps

  # qlik core stack
  helm upgrade --install qlik-core ./helm/qlik-core
  helm upgrade --repo https://qlik.bintray.com/osscharts --install mira mira
}

function grafana() {
  kubectl port-forward --namespace=monitoring $(kubectl get pods --namespace=monitoring --selector="app=grafana" -o=jsonpath='{.items[0].metadata.name}') 3000:3000
}

function remove_cluster() {
  gcloud container -q clusters delete $K8S_CLUSTER --project $GCLOUD_PROJECT --zone $GCLOUD_ZONE
}

function remove_disks() {
  gcloud compute -q disks delete $DISK_NAME --project $GCLOUD_PROJECT --zone $GCLOUD_ZONE
}

function wipe() {
  remove_cluster
  remove_disks
}

function external_ip() {
  kubectl get service nginx-ingress-controller
}

if [ "$command" == "bootstrap" ]; then bootstrap
elif [ "$command" == "upgrade" ]; then upgrade
elif [ "$command" == "copy-apps" ]; then copy_apps
elif [ "$command" == "remove-cluster" ]; then remove_cluster
elif [ "$command" == "remove-disks" ]; then remove_disks
elif [ "$command" == "wipe" ]; then wipe
elif [ "$command" == "ip" ]; then external_ip
elif [ "$command" == "grafana" ]; then grafana
else echo "Invalid option: $command - please use one of: bootstrap, upgrade, copy-apps, remove_cluster, remove_disks, wipe, ip, grafana"; fi
