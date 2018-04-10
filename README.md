# Autoscaling Kubernetes on GKE

## Prerequisites

* Setup GKE (Google Kubernetes Engine) by following this guide: https://cloud.google.com/kubernetes-engine/docs/quickstart

* Modify the `settings.config` for your needs. Do note that you **have to add your Project name**. Example: `GCLOUD_PROJECT="${GCLOUD_PROJECT:-YOUR-PROJECT-HERE}"` add your project name after `:-`

*  Accept the EULA, by modifying the file: `./qlik-core/engine-deployment.yaml`

## Create GKE cluster

Now create your cluster with the following command: 
```bash
./create-cluster.sh
```

This command will take some time, since now the GKE cluster and compute volume is being created.

After the script finished you should be able to query the Kubernetes cluster. To see some metric execute the following commands: 

Node metrics:

```bash
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq .
```

Pods metrics:

```bash
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods" | jq .
```
It might take some time before the metrics api finds the new metrics.

### Option 1 - Setting up Custom Metrics Server with a script

Run the `deploy.sh` script:
```bash
./deploy.sh
```

Continue with chapter [Add apps to the engine](#add-apps-to-the-engine)

### Option 2 - Setting up Custom Metrics Server step by step

Now we can scale on the built-in metrics which is CPU and Memory, but in order to scale based on custom metrics you need to have two components. 
One component that collects metrics from your applications and stores them the [Prometheus](https://prometheus.io) in a time series database.

And a second component that extends the Kubernetes custom metrics API with the metrics supplied by the collected metrics in Prometheus, the [k8s-prometheus-adapter](https://github.com/DirectXMan12/k8s-prometheus-adapter).

First, we need to create the namespaces for metrics and Ingress:

```bash
kubectl create -f ./namespaces.yaml
```

Increase priveleges to be able to deploy prometheus. Get your account name with: 
```bash
gcloud info | grep Account
```

Take the output of the above command and increase priveleges: 

```bash
kubectl create clusterrolebinding myname-cluster-admin-binding --clusterrole=cluster-admin --user=<ACCOUNT FROM ABOVE>
```

Deploy Prometheus:

```bash
kubectl create -f ./prometheus
```

Deploy the Prometheus custom metrics API adapter:

```bash
kubectl create -f ./custom-metrics-api
```

After the pods is in a ready state we should now be able to list the custom metrics provided by Prometheus:

```bash
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq .
```
It might take some time before the metrics api finds the qix metrics 

### Ingress routing

Deploy the ingress controller allowing us to reach the qix-session services and create sessions against engines in our cluster.

```bash
kubectl create -f ./ingress
```

### NFS volumes

Deploy the NFS server enabling us to have read/write volumes reachable by the engine pods.

```bash
kubectl create -f ./nfs-volumes
```

## Add apps to the engine

Run the seeding script to load the docs in `./doc` catalogue to the cluster.

```bash
./doc-seed.sh
```

## Auto Scaling based on custom metrics

Now let's deploy Qlik Core and start to scale based on Qix active sessions.

Start by adding ClusterRole for the Mira service
```bash
kubectl create -f ./rbac-config.yaml
```

The Docker images that are being used are not public, so you must add a secret to Kubernetes to be able to pull these images from Docker Hub.

To add this secret to Kubernetes, run the following command:

```bash
kubectl create secret docker-registry dockerhub --docker-username=<your-name> --docker-password=<your-password> --docker-email=<your-email>
```
Deploy Qlik Core:
```bash
kubectl create -f ./qlik-core
```

The `engine` service exposes a custom metric named `qix_active_sessions`. 
The Prometheus adapter removes the `_total` suffix and marks the metric as a counter metric.

Get the total qix_active_sessions from the custom metrics API:

```bash
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/qix_active_sessions" | jq .
```

Check that the HPA (Horizontal Pod Autoscaler), which is responsible for the scaling, is active and check that you have 0 sessions on your engines.

```bash
kubectl get hpa
```

## Add load to the cluster

Now we can apply some load on the `engine` service with [core-qix-session-workout](https://github.com/qlik-ea/core-qix-session-workout)

First, we need to clone the repository and change folder to the repository directory.

then we need to get the external ip-address from the nginx-controller which acts as the entrypoint to the cluster.

```
kubectl get service ingress-nginx --namespace ingress-nginx
```

Copy the external-ip and change the `gateway` field in the `configs/scaling.json` file to your ingress-nginx controllers external ip.

Then we can start putting some load on our engines.

```bash
node cli.js -c ./configs/scaling.json
```

This will create 50 sessions, one new session every 10 seconds with no selections being made. You can change the settings in the `configs/scaling.json` file if you want to scale up to more sessions or change the speed that new sessions are added with.

The HPA is configured to start scaling new engine pods when the average selection on the engines are more than 10 sessions. The session-service is configured to place a max of 20 sessions on one engine. The engine deployment itself is configured to only accept being on a node that doesn't have another engine running on it already.

Depending on how many nodes you already have it might put the new pod(s) on a node that already exists (that does not have an engine) or it might need to spin up one or several new nodes to be able to deploy the engine pod.

When all 50 sessions have been loaded on the engines you can stop the `core-qix-session-workout` by pressing `ctrl + c` in the terminal it is running.
HPA will then scale down the deployment to its initial number of replicas and nodes.

You may have noticed that the autoscaler doesn't react immediately to usage spikes. 
By default, the metrics sync happens once every **30 seconds** and scaling up/down can 
only happen if there was no rescaling within the last **3-5 minutes** with different timers for scaling the pods and the nodes. 
In this way, the HPA prevents rapid execution of conflicting decisions.


## Conclusions

Not all systems can meet their SLAs by relying on CPU/memory usage metrics alone, most web and mobile 
backends require autoscaling based on requests per second to handle any traffic bursts. 
For ETL apps, auto scaling could be triggered by the job queue length exceeding some threshold and so on. 
By instrumenting your applications with Prometheus and exposing the right metrics for autoscaling you can 
fine tune your apps to better handle bursts and ensure high availability.


## Removing the cluster
Remove the cluster with:
```bash
./remove-cluster.sh
```

### Known issues
If you are getting issues with the nginx deployment, you might have used all your public IP's. Make some public IP's available by clearing up here: https://console.cloud.google.com/net-services/loadbalancing/loadBalancers/list
