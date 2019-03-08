# Helm tutorial

WIP for seting up the core-scaling example using helm.

## Steps:

1) create the cluster normaly using `run.sh create` and run the function `create_role_binding` in the `run.sh` file as well
2) `cd helm`
3) `kubectl apply -f ./rbac-config.yaml` //I've added the rbac needed for tiller in this file as well
4) `helm init --service-account tiller`
5) `kubectl create secret generic license-data --from-literal LICENSES_SERIAL_NBR=$LICENSES_SERIAL_NBR --from-literal LICENSES_CONTROL_NBR=$LICENSES_CONTROL_NBR --dry-run -o=yaml | kubectl apply -f -`
6) Install the environment
``` 
helm install --name prometheus --namespace monitoring stable/prometheus
helm install --name custom-metrics-apiserver stable/prometheus-adapter --set prometheus.url=http://prometheus.monitoring.svc
kubectl apply -f ./grafana-datasources-cfg.yaml
kubectl apply -f ./grafana-dashboards-cfg.yaml
helm install --name grafana --namespace monitoring stable/grafana --set sidecar.datasources.enabled=true,sidecar.dashboards.enabled=trueenv.GF_AUTH_ANONYMOUS_ENABLED=true,env.GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
helm install --name nginx-ingress stable/nginx-ingress -f ./ingress-values.yaml
helm install --name nfs-server ./nfs
```
The grafana configs needs to exist before the grafana chart is installed, otherwise order should not matter

7) copy the docs using the `run.sh` function `doc_seed`

8) install core-scaling
```
helm install --name qlik-core ./qlik-core
helm repo add qlikoss https://qlik.bintray.com/osscharts
helm install --name qlikoss/mira
```


Not working:

* The HPA and Grafana does not seem to reach promethues
* The Ingess does not work, I cant reach the session service from outside the cluster

Improvements:

* Change the engine chart to be a copy of the official one.
* Modify the `run.sh` script to use helm
* Currently we install serveral charts. Perhaps it should be changed to one "core-scaling" chart with the external charts as dependencies. I dont know which is the proper way.
* Modify the core-sclaing specific charts we have to either a) simplify them and have them as example and not make them very extendable but simpler or b) make them more extendable and have less hardcoded values