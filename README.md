# k8s-prom-hpa

### Prerequisites

Setup GKE (Google Kubernetes Engine) by following this guide: https://cloud.google.com/kubernetes-engine/docs/quickstart

You need to set the variable GCLOUD_PROJECT, either in console or in the `settings.config` file.

Create your cluster with the following command: 
```bash
gcloud container --project "api-project-97421487144" clusters create "hcacluster" --zone "europe-west2-a" --username "admin" --cluster-version "1.9.6-gke.0" --machine-type "n1-standard-1" --image-type "COS" --disk-size "50" --scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "3" --network "default" --enable-cloud-logging --enable-cloud-monitoring --subnetwork "default" --enable-autoscaling --min-nodes "2" --max-nodes "6" --addons KubernetesDashboard
```

Create a persistent disk for Apps: 

`gcloud compute disks create --size=10GB --zone=europe-west2-a app-nfs-disk`


This demo asumes that you have a kubernetes cluster with version 1.9.3 or later with a metrics server deployed running somewhere that supports and have enabled autoscaling of nodes.

Make sure you are able to query the metrics api: 

```bash
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" | jq .
```

View pods metrics:

```bash
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/pods" | jq .
```


### Setting up a Custom Metrics Server 

In order to scale based on custom metrics you need to have two components. 
One component that collects metrics from your applications and stores them the [Prometheus](https://prometheus.io) time series database.
And a second component that extends the Kubernetes custom metrics API with the metrics supplied by the collect, the [k8s-prometheus-adapter](https://github.com/DirectXMan12/k8s-prometheus-adapter).

You will deploy Prometheus and the adapter in a dedicated namespace. 

Create the `monitoring` namespace:

```bash
kubectl create -f ./namespaces.yaml
```

Increase priveleges to be able to deploy prometheus
```bash
gcloud info | grep Account
```

Take the output of the above command and increase priveleges: 

```bash
kubectl create clusterrolebinding myname-cluster-admin-binding --clusterrole=cluster-admin --user=<ACCOUNT FROM ABOVE>
```

Deploy Prometheus v2 in the `monitoring` namespace:

```bash
kubectl create -f ./prometheus
```

Deploy the Prometheus custom metrics API adapter:

```bash
kubectl create -f ./custom-metrics-api
```

List the custom metrics provided by Prometheus:

```bash
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1" | jq .
```

Get the FS usage for all the pods in the `monitoring` namespace:

```bash
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/monitoring/pods/*/fs_usage_bytes" | jq .
```

### Ingress routing

Deploy Ingress:
```bash
kubectl create -f ./ingress
```

### Volumes
Add volumes:
```bash
kubectl create -f ./volume
```

### Auto Scaling based on custom metrics

Let's deploy Qlik Core and start to scale based on Qix active sessions.

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

Check that the Horizontal Pod Autoscaler is active and check that you have 0 sessions on your engines.

```bash
kubectl get hpa
```

Deploy the ingress controller allowing us to reach the different services in our cluster. Most importantly allowing the `core-qix-session-workout`
to reach the engines and create sessions.

```bash
kubectl create -f ./ingress
```

Now we can apply some load on the `engine` service with [core-qix-session-workout](https://github.com/qlik-ea/core-qix-session-workout)

First we need to clone the repository and change folder to the repository directory.

then we need to get the external ip-adress from the nginx-controller which acts as the entrypoint to the cluster.

```
kubectl get service ingress-nginx --namespace ingress-nginx
```

Copy the external-ip and change the `gateway` field in the `configs/scaling.json` file to your ingress-nginx controllers external ip.

Then we can start putting some load on our engines.

```bash
node cli.js -c ./configs/scaling.json
```

This will create 50 sessions, one new session every 10 seconds with no selections being made. You can change the settings in the `configs/scaling.json` file if you want to scale up to more sessions or change the speed that new sessions are added with.

The HPA is configued to start scaling new engine pods when the average selection on the engines are more than 10 sessions. And the session-service is configured to place a max of 20 sessions on one engine. The engine deployment itself is configured to only accept being on a node that does not have another engine running on it already.

Depending on how many nodes you already have it might put the new pod(s) on a node that already exists (that does not have an engine) or it might need to spin up one or several new nodes to be able to deploy the engine pod.

You can see the status of the scale-up by running these commands in a different terminal:

```bash
kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1/namespaces/default/pods/*/qix_active_sessions"
```
to see the metrics value of qix_active_sessions or 

```bash
kubectl get hpa
```

to see the status of the Horizontal Pod Autoscaler.

When all 50 sessions have been loaded on the engines you can stop the `core-qix-session-workout` by pressing `ctrl + c` in the terminal it is running inside.
the HPA will then scale down the deployment to it's initial number of replicas and nodes.

You may have noticed that the autoscaler doesn't react immediately to usage spikes. 
By default the metrics sync happens once every 30 seconds and scaling up/down can 
only happen if there was no rescaling within the last 3-5 minutes with different timers for scaling the pods and the nodes. 
In this way, the HPA prevents rapid execution of conflicting decisions.

### Delete cluster
Remove the cluster with:
```bash
gcloud container clusters delete <CLUSTER-NAME>
```

Remove the volume:
```bash
gcloud compute disks delete app-nfs-disk
```



### Conclusions

Not all systems can meet their SLAs by relying on CPU/memory usage metrics alone, most web and mobile 
backends require autoscaling based on requests per second to handle any traffic bursts. 
For ETL apps, auto scaling could be triggered by the job queue length exceeding some threshold and so on. 
By instrumenting your applications with Prometheus and exposing the right metrics for autoscaling you can 
fine tune your apps to better handle bursts and ensure high availability.
