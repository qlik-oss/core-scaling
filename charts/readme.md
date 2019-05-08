# Helm tutorial

In general, check the `../run.sh` file for implementation details.

1) create the cluster (including disks/monitoring stack, secrets, etc.): `./run.sh bootstrap`
2) Deploy/upgrade: `./run.sh upgrade`
3) Wipe: `./run.sh wipe`

# Todo

* Move qlik core helm stack to core-orchestration, and use as dependency here instead
* Consume the official engine chart?
* Introduce chart-of-charts with dependencies: https://github.com/codefresh-io/helm-chart-examples/tree/master/chart-of-charts and remove `run.sh` in favor of vanilla helm
* Fix Circle CI build master
* Remove namespaces
* remove node selector - use labels. 
* rollback

HOW DO WE HANDLE ACCEPT EULA... 