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

## Upgrading to 3.2.7

Chart 3.2.7 changes `parseable.datasets` from a list into a reconciliation
object. Existing dataset values must be migrated before upgrading:

- Move the old dataset list under `datasets.items`.
- Add `datasets.enabled: true` to manage datasets.
- Add the required `telemetryType` and `logSource` fields to every item.
- Keep the existing `retention.duration` and `retention.action` fields.
  `action` currently supports only `delete`.

```yaml
# Before 3.2.7
parseable:
  datasets:
    - name: sample-dataset
      retention:
        action: delete
        duration: 30d

# 3.2.7 and newer
parseable:
  datasets:
    enabled: true
    items:
      - name: sample-dataset
        telemetryType: logs
        logSource: json
        retention:
          action: delete
          duration: 30d
```

This also changes lifecycle behavior. Before 3.2.7, the chart only created or
updated datasets listed in values. In 3.2.7, `enabled: true` makes `items` the
complete desired set: user datasets absent from the list are deleted, including
their data, and `items: []` requests deletion of all user datasets. Review the
list before upgrading. To preserve the old `datasets: []` behavior and leave
existing datasets unchanged, omit `datasets` or use:

```yaml
parseable:
  datasets:
    enabled: false
```

When removing only a retention rule, keep the dataset in `items`, set
`retention.duration` to `0d` or an empty string, and retain `action: delete`.
Installations that did not list any datasets are unaffected after removing the
legacy `datasets: []` value or replacing it with `enabled: false` as above.

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
  --from-literal=username=admin \
  --from-literal=password=admin

helm install parseable ./ -n parseable -f overlays/standalone.yaml
```

For Enterprise standalone on `v3.2.8` or newer, add these values to the
standalone overlay. Keep `parseable.image` for OSS; the Enterprise image belongs
under `parseable.enterprise.image`.

```yaml
parseable:
  deploymentMode: standalone
  enterprise:
    enabled: true
    image:
      repository: quay.io/parseablehq/parseable-enterprise
      tag: v3.2.8
      pullPolicy: IfNotPresent
  store:
    type: local-store
    secretName: parseable-env-secret
```

The built-in license is used when `enterprise.license` is empty. To install a
provided license JSON, set `enterprise.license.secretName` and `dataKey` as
described below. Enterprise standalone does not support legacy mounted license
files or signatures.

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
  --from-literal=username=admin --from-literal=password=admin \
  --from-literal=s3.url=<endpoint> \
  --from-literal=s3.access.key=<key> --from-literal=s3.secret.key=<secret> \
  --from-literal=s3.bucket=<bucket> --from-literal=s3.region=<region>

helm install parseable ./ -n parseable -f overlays/aws.yaml
```

### GCP (GCS)

```sh
kubectl -n parseable create secret generic parseable-env-secret \
  --from-literal=username=admin --from-literal=password=admin \
  --from-literal=gcs.url=<url> --from-literal=gcs.bucket=<bucket>

kubectl -n parseable create secret generic parseable-gcs-key \
  --from-file=key.json=<path-to-service-account-key.json>

helm install parseable ./ -n parseable -f overlays/gcp.yaml
```

### Azure (Blob)

```sh
kubectl -n parseable create secret generic parseable-env-secret \
  --from-literal=username=admin --from-literal=password=admin \
  --from-literal=azr.access_key=<key> --from-literal=azr.account=<account> \
  --from-literal=azr.container=<container> \
  --from-literal=azr.url=https://<account>.blob.core.windows.net

helm install parseable ./ -n parseable -f overlays/azure.yaml
```

## Enterprise distributed (adds prism)

Stack `overlays/enterprise.yaml` on top of an object-store overlay. The chart's
default Enterprise image uses the built-in license. The overlay keeps its
separate cluster Secret for existing installations. For custom Enterprise
values without `clusterSecret.enabled: true`, add a `cluster.secret` key to the
store Secret instead (for example,
`--from-literal=cluster.secret="$(openssl rand -hex 8)"`). All Enterprise
distributed nodes then read it from `store.secretName`. For a release older
than `v3.2.7`, provide a legacy license Secret:

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
Images older than `v3.2.7` require the legacy license and signature settings.

The chart applies the provided file after the deployment starts. Enterprise
nodes load the license from object storage. The file must be a single JSON
object with base64-encoded `license` and `signature` fields. The credentials in
the configured store Secret must belong to a super-admin in multi-tenant mode.

For existing deployments, keep the legacy settings during an image-only upgrade.
For a newer image, remove `signature` to apply a combined JSON through the API
Job, or remove the entire `license` block to use the built-in default.

## Resources as code

Datasets, API keys, dashboards, alert targets, and alerts can be reconciled on
install and upgrade. Each resource section follows the same lifecycle rules:

- Omit the section or set `enabled: false` to leave server resources unchanged.
- Set `enabled: true` and provide `items`; the list becomes the complete desired
  set, not a partial list.
- An empty `items: []` requests deletion or revocation of every managed resource
  of that type. Resources created through the UI can also be removed.

Review the desired lists carefully before upgrading a release. Datasets are
reconciled before API keys, dashboards, targets, and alerts; targets are applied
before alerts and obsolete targets are removed after alert reconciliation.

## Datasets

Set `parseable.datasets.enabled: true` and provide the complete dataset list.
Every item requires `name`, `telemetryType`, and `logSource`. OpenTelemetry
sources must match their telemetry type: `otel-logs`/`logs`,
`otel-metrics`/`metrics`, or `otel-traces`/`traces`. Dataset names, telemetry
types, and log sources cannot be changed in place. Renaming a dataset creates a
new one and deletes the old dataset, including its data.

```yaml
parseable:
  datasets:
    enabled: true
    items:
      - name: payment-traces
        telemetryType: traces
        logSource: otel-traces
        tags: [agent-observability]
        retention:
          duration: 30d
          action: delete
        smartCache:
          size: 10Gi
```

Retention duration must be `1d` through `3650d`; use `0d` or `""` to remove
the rule. `action` is required whenever `retention` is present and only `delete`
is supported. Smart Cache is Enterprise-only, has a 10 GiB minimum, and can be
removed with `0Gi` or `""`. Ensure the querier has enough hot-tier capacity.
The `agent-observability` tag requires a traces/`otel-traces` dataset.

## API keys

Set `parseable.apiKeys.enabled: true` and provide the complete key list. Each
item requires a unique `name` and an `apiKeyType` of `ingestor` or `query`.
Omit `secretKeyRef` to let Parseable generate a value for a new key; the value
is printed once in Job output and may therefore be retained by CI logs. Save it
securely. To supply a key, store an RFC 4122 UUID v4 in a Secret in the release
namespace and reference its field. Never put key values directly in values.

```yaml
parseable:
  apiKeys:
    enabled: true
    items:
      - name: payment-ingest
        apiKeyType: ingestor
        secretKeyRef:
          name: parseable-api-keys
          key: PAYMENT_KEY
      - name: payment-query
        apiKeyType: query
```

Changing `apiKeyType` requires revoking and recreating the key. With
`enabled: true`, keys absent from `items` are revoked; `items: []` revokes all
keys.

## Dashboards from values or ConfigMaps

Set `parseable.dashboards.enabled: true` and list dashboards under `items`.
Use `json` for a complete exported dashboard or `configMap` for the exact name
of a ConfigMap that already contains one dashboard JSON entry. The JSON key
inside that ConfigMap can have any name.

```yaml
parseable:
  dashboards:
    enabled: true
    items:
      - name: payments
        json: |
          {"tiles": []}
      - name: orders
        configMap: orders-dashboard
        namespace: parseable
      - name: operations
        configMap: operations-dashboard
        namespace: monitoring
```

`name` becomes the dashboard title. Each dashboard entry must provide exactly one of
`json` or `configMap`. Each `configMap` item needs `namespace`, including
ConfigMaps in the release namespace. The chart creates a ConfigMap for each
inline dashboard and grants the Job read access to referenced ConfigMaps.
Your Helm installer needs permission to create a Role and RoleBinding in each
referenced namespace.

The Job validates every dashboard before changing Parseable. The list is the
complete desired set: dashboards missing from it are deleted, including
dashboards created in the UI. Set `items: []` to delete all dashboards.
Omit `dashboards` or set `enabled: false` to leave them unchanged. Run
`helm upgrade` to apply changes to values or referenced ConfigMaps.

## Alerts from values or ConfigMaps

Set `parseable.alerts.enabled: true` and list alerts under `items`. Use `json`
for complete exported alert JSON or `configMap` for the exact name of an
existing ConfigMap with one JSON entry in `data`. The key can have any name.
For either source, optional `name` overrides the JSON `title`; otherwise
the JSON `title` is used. Keep target ULIDs in the `targets` list; configure
targets with `parseable.targets` or create them in Parseable first.

```yaml
parseable:
  alerts:
    enabled: true
    items:
      - name: Payment failures # Optional title override
        json: |
          {
            "severity": "high",
            "title": "Payment errors",
            "query": "SELECT COUNT(*) AS count FROM payment_logs HAVING count > 0",
            "queryType": "builder",
            "datasets": ["payment_logs"],
            "alertType": "threshold",
            "thresholdConfig": {"operator": ">", "value": 0},
            "evalConfig": {"rollingWindow": {"evalStart": "1 day", "evalEnd": "now", "evalFrequency": 10}},
            "targets": ["01H7Z0XQ9G6K3JY1F5Z2X8V4E3"],
            "notificationConfig": {"interval": 1}
          }
      - name: Order failures # Optional title override
        configMap: orders-alert
        namespace: parseable
      - configMap: operations-alert
        namespace: monitoring
```

Each alert entry must have exactly one of `json` or `configMap`. The chart creates a
ConfigMap for inline JSON. Each `configMap` item needs `namespace`, including
ConfigMaps in the Helm release namespace. The Job gets read-only access to the
referenced ConfigMaps; the Helm installer needs permission to create a Role and
RoleBinding in each referenced namespace.

Targets are reconciled before alerts. The Job validates all alert JSON and
target references before making API changes. An alert without `id` is matched
by its unique title; include its existing ID to rename it. The alert list is
the complete desired set: alerts absent from it are deleted, including
UI-created alerts. Set `items: []` to delete all alerts. Omit `alerts`
or set `enabled: false` to leave them unchanged. Run `helm upgrade` to apply
changes to values or referenced ConfigMaps.

## Alert targets

Set `parseable.targets.enabled: true` and provide the complete target list.
Every item requires a stable 26-character ULID `id`, a unique `title`, a `type`
of `slack`, `webhook`, or `alertManager`, and an `endpointSecretRef`. Endpoint
URLs and AlertManager credentials must be stored in Secrets in the release
namespace.

```yaml
parseable:
  targets:
    enabled: true
    items:
      - id: 01K9QQ9QC51KD43TE4HTJ4MW1D
        title: payments-webhook
        type: webhook
        endpointSecretRef:
          name: alert-target-secrets
          key: PAYMENTS_URL
        skipTlsCheck: false
        customHeaders:
          X-Team: payments
```

Webhook targets additionally accept `skipTlsCheck` and `customHeaders`.
AlertManager targets accept `skipTlsCheck` and require both
`usernameSecretRef` and `passwordSecretRef` when Basic Auth is used. Slack
targets accept no additional fields. Target titles cannot be changed in place,
and replacing an ID is blocked while an alert still uses the old target.

## Upgrade / Uninstall

```sh
helm upgrade parseable ./ -n parseable -f overlays/aws.yaml
helm uninstall parseable -n parseable
```
