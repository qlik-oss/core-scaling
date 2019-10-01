# Autoscaling Qlik Core on Google Kubernetes Engine

This use case shows how you can set up a Qlik Core application in a Google Kubernetes Engine (GKE) cluster so you can easily scale your application up or down to meet user demands.

## Prerequisites

* Set up Google CLI (`gcloud`) by following this guide [Quickstart guide](https://cloud.google.com/sdk/docs/quickstarts).

* Modify the `settings.config` for your project.

    !!! Note
        You must include your license serial number, license control number and Google Cloud project name in the `settings.config` file.
        You should add the license serial number, license control number and Google Cloud project name after the ":-" on the respective rows.

        Example: `GCLOUD_PROJECT="${GCLOUD_PROJECT:-YOUR-GLCOUD-PROJECT-NAME-HERE}"`

* Accept the EULA by modifying the `./qlik-core/engine-deployment.yaml` file.

* Change the max number of sessions on an engine from 500 to 20 by changing `SESSIONS_PER_ENGINE_THRESHOLD` in the `./qlik-core/qix-session-deployment.yaml` file.

* Change when the HPA will start scaling engines by changing `qix_active_sessions` from 250 to 10 in the `./qlik-core/engine-hpa-custom.yaml` file.

* Install [jq](https://stedolan.github.io/jq/) JSON processor to make the printout more readable.

## Issues

Before reporting a new issue, look for your issue in [Known issues](#known-issues).

## Getting started

There are two ways get started:

* By following the step-by-step guide below.

    If you are unfamiliar with GKE, we recommend that you follow the step-by-step guide.

* By deploying everything with the following command:

    ```bash
    ./run.sh deploy
    ```

    If you choose this option, you can skip to [Add load to the cluster](#add-load-to-the-cluster).

## Create a GKE cluster

!!! Note
    There is often a deployment delay before the services are running. If a command fails,
    wait 30 seconds and try again.

Create the GKE cluster with the following command:

```bash
./run.sh create
```

This command runs the script that creates the GKE cluster and volumes, and it will take some time to complete.

After the script is finished running, you should be able to query the Kubernetes cluster. Run the following commands to see the node and pods metrics:

* Node metrics:

    ```bash
    kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq .
    ```

* Pods metrics:

    ```bash
    kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods" | jq .
    ```

### Set up a custom metrics server

You can scale up or down based on built-in metrics: CPU and memory. However, to scale up or down based on custom metrics, you need to add two components.

You need one component to collect metrics from your applications and store them to [Prometheus](https://prometheus.io) in a time series database.

The second component extends the Kubernetes custom metrics API with the [k8s-prometheus-adapter](https://github.com/DirectXMan12/k8s-prometheus-adapter). The adapter talks to Prometheus to expose custom metrics and makes them available to the Kubernetes custom metrics API.

Do the following:

1. Create the namespaces for metrics and Ingress:

    ```bash
    kubectl create -f ./namespaces.yaml
    ```

1. Increase the privileges to deploy Prometheus:

    ```bash
    kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value core/account)
    ```

1. Deploy Prometheus:

    ```bash
    kubectl create -f ./prometheus
    ```

1. Deploy the Prometheus custom metrics API adapter:

    ```bash
    kubectl create -f ./custom-metrics-api
    ```

1. Once the pod is in a ready state, you can list the custom metrics provided by Prometheus:

    ```bash
    kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq .
    ```

### Ingress routing

Deploy the Ingress controller, which lets you reach the qix-session services and creates sessions against engines in our cluster.

```bash
kubectl create -f ./ingress
```

### NFS volumes

Deploy the NFS server, which gives read/write access of the volumes to the engine pods.

```bash
kubectl create -f ./nfs-volumes
```

## Add apps to the engine

Run the seeding script to load the documents in the `./doc` folder into the cluster.

```bash
./run.sh populate-docs
```

## Autoscaling based on custom metrics

Now that the GKE cluster is set up and the documents are loaded into the cluster, you can deploy Qlik Core and start to scale based on Qlik Associative Engine active sessions.

1. Add a ClusterRole for the Mira service.

    ```bash
    kubectl create -f ./rbac-config.yaml
    ```

1. Add a configmap with your license data

    ```bash
    kubectl create configmap license-data --from-literal LICENSE_KEY_=YOUR-LICENSE-KEY
    ```

1. Deploy Qlik Core:

    ```bash
    kubectl create -f ./qlik-core
    ```

    The `engine` service exposes a custom metric named `qix_active_sessions`.
    The Prometheus adapter removes the `_total` suffix and marks the metric as a counter metric.

1. Get the total Qlik Associative Engine active sessions from the custom metrics API:

    ```bash
    kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/qix_active_sessions" | jq .
    ```

1. Check that the Horizontal Pod Autoscaler (HPA), which is responsible for scaling, is active, and check that you have 0 sessions on your engines.

    ```bash
    kubectl get hpa
    ```

## Monitor the cluster

Before you add any load to the cluster, deploy Grafana for monitoring.

1. Deploy Grafana.

    ```bash
    kubectl create -f ./grafana
    ```

1. Expose the Grafana web server on a local port.

    ```bash
    ./run.sh grafana
    ```

You can view Grafana on http://localhost:3000.

## Add load to the cluster

Now that Grafana is set up, apply some load on the `engine` service with [core-qix-session-workout](https://github.com/qlik-oss/core-qix-session-workout).

First, clone the repository and go to the repository directory.

Next, you need to get the external IP address from the nginx-controller which acts as the entry point to the cluster.

1. Get the IP addresses from the nginx-controller.

    ```
    kubectl get service ingress-nginx --namespace ingress-nginx
    ```

1. Copy the external IP address and change the `host` field in the `configs/scaling.json` file to your ingress-nginx controllers external IP address.

    ```bash
    node main.js -c configs/scaling.json -s scenarios/random-selection-scenario.js
    ```

Now you can start putting some load on the engines.

### Results

This will create 50 sessions, one new session every 10 seconds with random selections being made every 2 seconds. You can change the settings in the `configs/scaling.json` file if you want to scale up to more sessions or change the speed at which new sessions are added.

The HPA is configured to start scaling new engine pods when the average selection on the engines exceeds 10 sessions. The session service is configured to place a maximum of 20 sessions on one engine. The engine deployment itself is configured to run one engine per node.

Depending on how many nodes you already have, the HPA might put a new pod on a node that already exists (that is not running an engine instance) or it might need to spin up one or several new nodes to be able to deploy the engine pod.

When all 50 sessions have been loaded on the engines, you can stop the `core-qix-session-workout` by pressing `ctrl + c` in the terminal it is running in. HPA will then scale down the deployment to its initial number of replicas and nodes.

You may have noticed that the autoscaler doesn't react immediately to usage spikes. This is because the metrics sync happens by default once every **30 seconds**. Scaling up/down can
only happen if there was no rescaling within the last **3-5 minutes** with different timers for scaling the pods and the nodes. As a result, the HPA prevents rapid execution of conflicting decisions.

## Conclusions

Not all systems can meet their SLAs by relying on CPU/memory usage metrics alone. Most web and mobile back-end systems require autoscaling based on requests-per-second to handle any traffic bursts.

For ETL apps, autoscaling can be triggered by the job queue length exceeding some threshold and so on. By instrumenting your applications with Prometheus and exposing the right metrics for autoscaling, you can fine-tune your applications to better handle traffic bursts and ensure high availability.

## Removing the cluster

Remove the cluster with:

```bash
./run.sh remove
```

### Known issues

* If you are having problems with the nginx deployment, you might have used all your public IPs. You can clear some IPs to make them available here: https://console.cloud.google.com/net-services/loadbalancing/loadBalancers/list

* If you are having problems when deploying Prometheus, it could be a problem with your username. When you get an error message, it should contain your actual username (case sensitive). Use this username and run this command before redeploying Prometheus.

    ```bash
    kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=<YOUR-USER-NAME>
    ```

* If you are running bash for Windows, you might have an issue with incorrect paths when querying kubectl for metrics. Use CMD instead of bash for Windows.

* If you are running on Windows `gcloud` might complain about python even if you have python 2.7 installed, a fix is to then rename the binary from `python.exe` to `python2.exe`

* If the cluster (API server) is unresponsive when you add load to your cluster, this is because the Kubernetes master node is being updated to match the size of the autoscaling cluster. To fix this, you have to deploy a regional cluster. Reade more here: https://cloudplatform.googleblog.com/2018/06/Regional-clusters-in-Google-Kubernetes-Engine-are-now-generally-available.html

### General Notes

* We have specified kubernetes requests and limits for our services. These, especially the values for the engine, should be tweaked if you use another node size.
