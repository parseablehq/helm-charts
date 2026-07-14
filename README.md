# Parseable Helm Charts

Helm charts for [Parseable](https://www.parseable.com) — a columnar data lake platform purpose-built for observability.

## Usage

```sh
helm repo add parseable https://charts.parseable.com
helm repo update
helm search repo parseable
```

## Charts

| Chart | Description | Docs |
| --- | --- | --- |
| `parseable` | Parseable (OSS and Enterprise), standalone or distributed, on local / S3 / GCS / Azure Blob storage. | [README](./charts/parseable/README.md) |
| `pai` | Parseable Auto Instrumentation (PAI) operator for Kubernetes. | [README](./charts/pai/README.md) |
