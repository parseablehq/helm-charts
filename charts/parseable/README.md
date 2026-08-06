# Parseable Helm Chart

```sh
helm repo add parseable https://charts.parseable.com
helm repo update

helm pull parseable/parseable --untar
cd parseable
```

`values.yaml` holds the defaults. Layer an overlay from `overlays/` with `-f` to
pick a topology / store, and stack `overlays/enterprise.yaml` for Enterprise.

```
overlays/
  standalone.yaml   single all-in-one pod (local-store)
  aws.yaml          distributed on S3
  gcp.yaml          distributed on GCS
  azure.yaml        distributed on Azure Blob
  enterprise.yaml   adds prism; layer on top of a store overlay
```

## Standalone (single pod, local-store)

For standalone, `standalone.unified.persistence.staging.enabled=true` creates a
staging PVC; setting it to `false` uses `emptyDir`.
With `local-store`, `standalone.unified.persistence.data.enabled=true` creates
a data PVC; setting it to `false` uses `emptyDir` for the data directory.
When local-store data is disabled, staging persistence must also be disabled;
persisted staging metadata cannot be paired safely with ephemeral local data.
With S3, GCS, or Azure Blob storage, no `/parseable/data` volume is created.

```sh
kubectl create namespace parseable

kubectl -n parseable create secret generic parseable-env-secret \
  --from-literal=addr=0.0.0.0:8000 \
  --from-literal=username=admin \
  --from-literal=password=admin

helm install parseable ./ -n parseable -f overlays/standalone.yaml
```

### Upgrading an existing standalone installation

Standalone now uses StatefulSet `volumeClaimTemplates`. Direct upgrades from
older fixed-PVC or `emptyDir` releases are blocked before Helm changes any
resources. Install a new release, migrate the required data, verify it, and then
move traffic.

## Distributed (querier + ingestors)

Create the namespace, then the object-store secret for your cloud (below).
With `distributed.ingestor.persistence.staging.enabled=true`, each ingestor
receives its own staging PVC; `false` uses `emptyDir`.
Distributed mode does not support `local-store`; use S3, GCS, or Azure Blob
Storage.

For Enterprise, `distributed.querier.persistence.hotTier.enabled=true` creates
one hot-tier PVC per querier; `false` uses `emptyDir`. These storage switches
are install-time choices. Changing either switch later requires recreating the
affected StatefulSet because its `volumeClaimTemplates` are immutable.

```sh
kubectl create namespace parseable
```

### AWS (S3)

```sh
kubectl -n parseable create secret generic parseable-env-secret \
  --from-literal=addr=0.0.0.0:8000 \
  --from-literal=username=admin --from-literal=password=admin \
  --from-literal=s3.url=<endpoint> \
  --from-literal=s3.access.key=<key> --from-literal=s3.secret.key=<secret> \
  --from-literal=s3.bucket=<bucket> --from-literal=s3.region=<region>

helm install parseable ./ -n parseable -f overlays/aws.yaml
```

### GCP (GCS)

```sh
kubectl -n parseable create secret generic parseable-env-secret \
  --from-literal=addr=0.0.0.0:8000 \
  --from-literal=username=admin --from-literal=password=admin \
  --from-literal=gcs.url=<url> --from-literal=gcs.bucket=<bucket>

kubectl -n parseable create secret generic parseable-gcs-key \
  --from-file=key.json=<path-to-service-account-key.json>

helm install parseable ./ -n parseable -f overlays/gcp.yaml
```

### Azure (Blob)

```sh
kubectl -n parseable create secret generic parseable-env-secret \
  --from-literal=addr=0.0.0.0:8000 \
  --from-literal=username=admin --from-literal=password=admin \
  --from-literal=azr.access_key=<key> --from-literal=azr.account=<account> \
  --from-literal=azr.container=<container> \
  --from-literal=azr.url=https://<account>.blob.core.windows.net

helm install parseable ./ -n parseable -f overlays/azure.yaml
```

## Enterprise (adds prism)

Stack `overlays/enterprise.yaml` on top of a store overlay, and create the license secret.

```sh
kubectl -n parseable create secret generic parseable-license \
  --from-file=parseable_license.json=<path>/parseable_license.json \
  --from-file=parseable_license.sig=<path>/parseable_license.sig

kubectl -n parseable create secret generic parseable-cluster-secret \
  --from-literal=cluster-secret="$(openssl rand -hex 8)"

helm install parseable ./ -n parseable \
  -f overlays/aws.yaml -f overlays/enterprise.yaml
```

## Upgrade / Uninstall

```sh
helm upgrade parseable ./ -n parseable -f overlays/aws.yaml
helm uninstall parseable -n parseable
```
