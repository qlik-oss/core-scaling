# k8s-prom-hpa
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

Take the output of tha above command and increase priveleges: 

```bash
kubectl create clusterrolebinding myname-cluster-admin-binding --clusterrole=cluster-admin --user=<OUTPUT FROM ABOVE>
```

Deploy Prometheus v2 in the `monitoring` namespace:

```bash
kubectl create -f ./prometheus
```

Generate the TLS certificates needed by the Prometheus adapter:

```bash
make certs
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


```bash
kubectl get hpa
```

Apply some load on the `engine` service with [workout](http://LINKEHERE)

```bash
Code for workout
```

After a few minutes the HPA begins to scale up the deployment:

```
kubectl describe hpa
```

After the load tests finishes, the HPA down scales the deployment to it's initial replicas.

You may have noticed that the autoscaler doesn't react immediately to usage spikes. 
By default the metrics sync happens once every 30 seconds and scaling up/down can 
only happen if there was no rescaling within the last 3-5 minutes. 
In this way, the HPA prevents rapid execution of conflicting decisions and gives time for the 
Cluster Autoscaler to kick in.

### Conclusions

Not all systems can meet their SLAs by relying on CPU/memory usage metrics alone, most web and mobile 
backends require autoscaling based on requests per second to handle any traffic bursts. 
For ETL apps, auto scaling could be triggered by the job queue length exceeding some threshold and so on. 
By instrumenting your applications with Prometheus and exposing the right metrics for autoscaling you can 
fine tune your apps to better handle bursts and ensure high availability.
