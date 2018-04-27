#!/bin/bash -v

set -e
echo "Creating cluster"
./create-cluster.sh
echo "Cluster created"

echo "Deploying"
./deploy.sh
echo "Deployment done"

echo "Waiting for deployment to run"
sleep 45

echo "Adding docs"
./doc-seed.sh
echo "Docs added"

echo "Add cluster role"
kubectl create -f ./rbac-config.yaml
echo "Cluster role added"

echo "Deploy Qlik Core"
kubectl create -f ./qlik-core
echo "Qlik Core deployed"

echo "Deploy grafana"
kubectl create -f ./grafana
echo "Grafana deployed"

echo "External IP:"
kubectl get service ingress-nginx --namespace ingress-nginx

echo "Waiting for Grafana"
sleep 20

echo "Port forward to Granfa"
./port-forward-grafana.sh
