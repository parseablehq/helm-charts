# Parseable Helm Charts

Helm charts for [Parseable](https://www.parseable.com) — a columnar data lake platform purpose-built for observability.

## Charts

| Chart | Description |
| --- | --- |
| [`parseable`](./parseable) | Parseable (OSS and Enterprise), standalone or distributed, on local / S3 / GCS / Azure Blob storage. |

## Usage

Until a hosted repository index is published, install directly from a clone:

```sh
git clone https://github.com/parseablehq/helm-charts.git
cd helm-charts/parseable

# standalone (single pod, local-store)
helm install parseable . -n parseable --create-namespace -f overlays/standalone.yaml

# distributed on a cloud (see overlays/ and the chart README)
helm install parseable . -n parseable -f overlays/aws.yaml
```

See the [chart README](./parseable/README.md) for full instructions, the
`overlays/` directory for per-cloud and enterprise examples, and `values.yaml`
for all configuration.
