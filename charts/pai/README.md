# PAI Helm Chart

Parseable Auto Instrumentation (PAI) operator for Kubernetes. Watches workloads
and configures OpenTelemetry auto-instrumentation via the
`ParseableConfig` CRD.

## Install

```sh
helm repo add parseable https://charts.parseable.com
helm repo update

kubectl create namespace pai

helm install pai parseable/pai -n pai
```

## Configuration

Key values in `values.yaml`:

```yaml
image:
  repository: parseable/pai
  tag: "v1"

resources:
  limits:
    cpu: 500m
    memory: 128Mi
  requests:
    cpu: 10m
    memory: 64Mi
```

## Upgrade / Uninstall

```sh
helm upgrade pai parseable/pai -n pai
helm uninstall pai -n pai
```
