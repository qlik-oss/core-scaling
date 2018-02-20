# Azure AKS Deployment Prototype

Prototyping work has been done to deploy the Assisted Prescription application to Kubernetes on Azure using AKS.
The base components needed for the application are included in the deployment, but not the ELK stack, nor the Prometheus
monitoring capabilities.

The sections below cover how to get the deployment up on AKS.

An Azure AKS cluster must be created to host the deployment. This can be done user either using the Azure CLI or using
the Azure portal. It is assumed that an account to use on Azure exists.

## Install Tools

- Install kubectl - https://kubernetes.io/docs/tasks/tools/install-kubectl  
  (Verified with v1.8.0)
- Install Azure CLI - https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest

### SSH keys

SSH keys are needed to create the cluster. The command `az aks create` can do this automatically using the
`--generate-ssh-keys` option but we will provide our own keys. Using `openssl`:

```sh
openssl.exe req -x509 -nodes -days 365 -newkey rsa:2048 -keyout azure-private.key -out azure-cert.pem
openssl.exe rsa -pubout -in azure-private.key -out azure-public.key
ssh-keygen -f azure-public.key -i -mPKCS8 > azure-public_ssh-rsa
```

## Create the AKS Cluster

**NOTE**: In the steps that follow it is assumed that the Azure Resource Group used is named `assisted-rg` and that the AKS
cluster created is called `assisted-cluster`. If other names are used, commands etc must be changed accordingly.

Before creating the cluster a new Application Registration must be done, followed by creating a Service Principal.
This is described in the first steps
[here](https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough-portal#create-service-principal).

Then create a **single node** cluster by also following the instructions
[here](https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough-portal#create-aks-cluster). Make sure to use
the public SSH key that was created in the previous step. Skip the part of deploying the Voting example application.

## Copy Application Data

Data sources used by the Assisted Prescription applicatin must be copied to the cluster node. This is a bit awkward and
steps follow to do this. There might be much more efficient ways to do this.

### Set Up Temporary Public IP Address

The Kubernetes cluster VM created has no public IP address so it is not possible to copy files to it using `scp`
unless a public IP address is assigned to it first. This is pretty straight-forward. Details are omitted, but the main
steps are as follows:

1. Create a Public IP resource in Azure under the same Resource Group as the AKS cluster.
1. Associate the IP to the Network Interface of the cluster.
1. Verify that the cluster VM has the public IP address and it should now be possible to `scp` to it.

### Copy the Files

In the commands below, replace `<NODE-IP>` with the public IP of the cluster node.

```sh
cd K8s
scp -i azure-private.key -r ../data/doc/ azureuser@<NODE-IP>:/home/azureuser
scp -i azure-private.key -r ../data/csv/ azureuser@<NODE-IP>:/home/azureuser
```

### Remove the Public IP Address

We only created the public IP so that files could be copied. It can now be removed using the Azure portal:

1. Disassociate the Public IP Address from the Network Interface of the cluster 
1. Remove the Public IP Address resource from Azure

## Prepare Secrets

Before the application can be deployed, Kubernetes secrets must be manyally created in the cluster. Replace `...` below
with your Docker Hub secrets to use. Make sure to use credentials that have access to the Docker images used.

```sh
cd K8s
 kubectl create secret docker-registry dockerhub --docker-username=... --docker-password=... --docker-email=...
kubectl create secret generic accounts --from-file=../secrets/ACCOUNTS
kubectl create secret generic jwt-secret --from-file=../secrets/JWT_SECRET
kubectl create secret generic cookie-signing --from-file=../secrets/COOKIE_SIGNING
```

## Deploy

Deploy services and deployments to the cluster with:

```sh
$ cd K8s
$ kubectl create -f plain/app/
deployment "auth" created
service "auth" created
deployment "engine" created
service "engine" created
deployment "mira" created
service "mira" created
deployment "openresty" created
service "openresty" created
deployment "qix-session" created
service "qix-session" created
deployment "redis" created
service "redis" created
```

## Watch the LoadBalancer Provisioning

```sh
$ kubectl get service openresty --watch
NAME        TYPE           CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE
openresty   LoadBalancer   10.0.11.79   <pending>     443:30746/TCP   19s 
```

This can take several minutes and once the external IP is established, something similar to this is shown:

```sh
NAME        TYPE           CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE
openresty   LoadBalancer   10.0.11.79   13.95.214.212   443:30746/TCP   3m
```

## Launch the Application

Open a browser and navigate to https://\<EXTERNAL-IP> (where `<EXTERNAL-IP>` is replaced with the actual IP given above.

Sign in with a "local" identity provided (e.g. `admin:password`) and the Assisted Prescription UI should be displayed.

## Launch the Kubernetes Dashboard

The Azure CLI tool can be used to launch the Kubernetes dashboard in AKS:

```sh
az aks browse --resource-group assisted-rg --name assisted-cluster
```
