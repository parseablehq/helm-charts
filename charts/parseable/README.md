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

New installations are not affected. If standalone Parseable was installed with
chart 3.0.2 or earlier, do not upgrade it directly to chart 3.1.0. Create a
separate installation, migrate and verify the data, and then move traffic.

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

Set annotations under each PVC's own persistence or cache config, for example:

```yaml
parseable:
  distributed:
    ingestor:
      persistence:
        staging:
          annotations:
            example.com/backup: "true"
```

The same `annotations` setting is available under standalone
`persistence.data` and `persistence.staging`, distributed querier
`persistence.hotTier`, and prism `persistence` and `cache`. Each applies only to
its own PVC. Leave it empty when upgrading an existing StatefulSet.
Adding or changing an annotation in `volumeClaimTemplates` on an existing
StatefulSet is rejected by Kubernetes. The template only affects new PVCs; it
does not update PVCs that already exist.

The distributed ingestor readiness-wait init container accepts CPU and memory
requests and limits under `distributed.ingestor.initContainer.resources`. In
Enterprise mode, the querier's prism readiness-wait container uses
`distributed.querier.initContainer.resources`. Both default to requests of
20m CPU and 16Mi memory, and limits of 250m CPU and 64Mi memory. For example,
to override the ingestor's requests:

```yaml
parseable:
  distributed:
    ingestor:
      initContainer:
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
```

The same readiness-wait init containers run the image set under `waitImage`
(`docker.io/curlimages/curl`, pinned to a release rather than `latest`), and
take a container security context under `initContainer.securityContext` beside
`resources`. The default meets the Pod Security `restricted` profile: no
privilege escalation, a read-only root filesystem, every capability dropped,
the `RuntimeDefault` seccomp profile, and the image's own non-root user by its
numeric id. To pull the image from a mirror:

```yaml
parseable:
  waitImage:
    repository: registry.example.com/mirror/curlimages/curl
    tag: "8.23.0"
```

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

Stack `overlays/enterprise.yaml` on top of a store overlay. The chart's default
Enterprise image still requires the legacy license Secret:

```sh
kubectl -n parseable create secret generic parseable-license \
  --from-file=parseable_license.json=<path>/parseable_license.json \
  --from-file=parseable_license.sig=<path>/parseable_license.sig

kubectl -n parseable create secret generic parseable-cluster-secret \
  --from-literal=cluster-secret="$(openssl rand -hex 8)"

helm install parseable ./ -n parseable \
  -f overlays/aws.yaml -f overlays/enterprise.yaml
```

For Enterprise image `v3.2.7` or newer, omit `license` to start with the
built-in 50 GB license:

```yaml
parseable:
  enterprise:
    enabled: true
    image:
      tag: v3.2.7
```

To install a license JSON through the helm, create a Secret with the
JSON file and set `secretName` and `dataKey`:

```sh
kubectl -n parseable create secret generic parseable-license \
  --from-file=license.json=<path>/license.json
```

```yaml
parseable:
  enterprise:
    image:
      tag: v3.2.7
    license:
      secretName: parseable-license
      dataKey: license.json
```
Images older than `v3.2.7` require this legacy configuration.

The chart applies the provided file after the deployment starts. Enterprise
nodes load the license from object storage. The file must be a single JSON
object with base64-encoded `license` and `signature` fields. The credentials in
the configured store Secret must belong to a super-admin in multi-tenant mode.

For existing deployments, keep the legacy settings during an image-only upgrade.
For a newer image, remove `signature` to apply a combined JSON through the API
Job, or remove the entire `license` block to use the built-in default.

## Dashboards from GitHub

Commit exported dashboard JSON files under one directory in a GitHub repository,
for example `dashboards/payments.json`. The filename (`payments`) becomes the
dashboard title. The chart reads only that directory and its subdirectories;
users do not need to clone the chart or create dashboard ConfigMaps.

Store a GitHub token with **Contents: read** access in a Secret in the
Parseable namespace, even for public repositories. Reference the Secret in
values; do not put the token itself in values.

```yaml
parseable:
  dashboards:
    enabled: true
    git:
      repository: https://github.com/company/observability-config.git
      ref: main
      path: dashboards
      secretKeyRef:
        name: dashboard-git-access
        key: token
```

The Job reads one commit snapshot on each Helm install or upgrade, validates
every JSON file, then creates or updates dashboards by title. Dashboards absent
from the Git directory are deleted, including dashboards created through the UI.
A missing folder or a folder without `.json` files fails without deleting
anything. Pushing to Git alone does not run the Job.

## Alerts from GitHub

Commit exported alert JSON files to a GitHub folder. Each JSON file's `title`
sets the alert title; its filename can be anything ending in `.json`. Keep
notification target IDs in the JSON `targets` list. Configure those targets
with `parseable.targets` in values before applying alerts that use them.

```yaml
parseable:
  alerts:
    enabled: true
    git:
      repository: https://github.com/company/observability-config.git
      ref: main
      path: alerts
      secretKeyRef:
        name: observability-git-access
        key: token
```

The token Secret needs GitHub **Contents: read** access, including for public
repositories. The Job reads a single commit snapshot, validates every JSON
file, then creates or updates alerts using the JSON title and optional ID.
Alerts absent from Git are deleted, including UI-created alerts. A missing
folder or one without `.json` files fails without deleting alerts. A Git push
alone does not run the Job; run `helm upgrade` to apply changes.

## Upgrade / Uninstall

```sh
helm upgrade parseable ./ -n parseable -f overlays/aws.yaml
helm uninstall parseable -n parseable
```
