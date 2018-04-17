kubectl port-forward --namespace=monitoring $(kubectl get pods --namespace=monitoring --selector="app=grafana" -o=jsonpath='{.items[0].metadata.name}') 3000:3000
