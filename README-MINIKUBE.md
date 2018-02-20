# Minikube Deployment Prototype

Prototyping work has been done to deploy the Assisted Prescription application to Kubernetes using Minikube. The base
components needed for the application are included in the deployment, but not the ELK stack, nor the Prometheus
monitoring capabilities.

The sections below cover how to get the deployment up on a developer machine using Minikube.

## Install Tools

- Install kubectl - https://kubernetes.io/docs/tasks/tools/install-kubectl
  (Verified with v1.8.0)
- Install Minikube - https://kubernetes.io/docs/tasks/tools/install-minikube/#install-minikube
  (Verified with v0.24.1)

## Start the Minikube VM

Start a Minikube VM with Kubernetes version 1.8.0 (probably works on later versions as well). The example below shows
how it can be done in a Windows environment:

```sh
$ minikube start --vm-driver hyperv --hyperv-virtual-switch MainSwitchEth --memory 4096 --kubernetes-version v1.8.0
```

Note how the HyperV VM manager and the virtual swith is specified with the options
`--vm-driver hyperv --hyperv-virtual-switch MainSwitchEth`. The deployment has been verified to be workig on a VM with
4096 MB of RAM.

## Copy Application Data

Copy the data files used by the application to the Minikube VM with (use default password `tcuser`):

```sh
cd plain
scp -r ../data/doc/ docker@$(minikube ip):/home/docker
scp -r ../data/csv/ docker@$(minikube ip):/home/docker
```

## Prepare Secrets

Manually create secrets in the Kubernetes cluster with (replace Docker Hub creds with actual creds):

```sh
cd plain
kubectl create secret docker-registry dockerhub --docker-username=... --docker-password=... --docker-email=...
```

## Deploy

Deploy services and deployments to the cluster with:

```sh
$ cd plain
$ kubectl create -f app/
deployment "engine" created
service "engine" created
deployment "mira" created
service "mira" created
deployment "openresty" created
service "openresty" created
deployment "qix-session" created
service "qix-session" created
```

## Launch the Minikube Dashboard

Observe that all workloads get deployed and get to running state by launchg the dashboard:

```sh
minikube dashboard
```

## Launch the Application

Chek the IP address of the Minkube VM. For example, with:

```sh
minikube ip
```

Open a browser and navigate to https://<Minikube VM IP>:31704.
