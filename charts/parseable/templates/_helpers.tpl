{{/*
Expand the name of the chart.
*/}}
{{- define "parseable.name" -}}
{{- default .Chart.Name .Values.parseable.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "parseable.fullname" -}}
{{- if .Values.parseable.fullnameOverride }}
{{- .Values.parseable.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.parseable.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Give invalid as-code section shapes a useful error before Helm renders a Job. */}}
{{- define "parseable.validateAsCodeSection" -}}
{{- if and (hasKey .values .section) (not (kindIs "map" (index .values .section))) -}}
  {{- fail (printf "parseable.%s must use enabled and items. Example: %s: {enabled: true, items: []}. Omit it or set enabled: false to skip." .section .section) -}}
{{- end -}}
{{- end -}}

{{/*
Give each inline dashboard a stable, readable ConfigMap name.
The short hash distinguishes names that normalize to the same Kubernetes name.
*/}}
{{- define "parseable.inlineDashboardConfigMapName" -}}
{{- if not (kindIs "string" .name) -}}
  {{- fail (printf "dashboards[%d].name is required and must be a nonempty string." .index) -}}
{{- end -}}
{{- if not (trim .name) -}}
  {{- fail (printf "dashboards[%d].name is required and cannot be blank." .index) -}}
{{- end -}}
{{- $fullname := include "parseable.fullname" .root -}}
{{- $slug := regexReplaceAll "[^a-z0-9]+" (lower (trim .name)) "-" | trimAll "-" -}}
{{- $slug = default "item" $slug | trunc 23 | trimSuffix "-" -}}
{{- $hash := sha256sum (printf "%s/%s" $fullname (trim .name)) | trunc 8 -}}
{{- printf "%s-dashboard-%s-%s" ($fullname | trunc 20 | trimSuffix "-") $slug $hash -}}
{{- end -}}

{{/* Name inline alert ConfigMaps from the item name or exported JSON title. */}}
{{- define "parseable.inlineAlertConfigMapName" -}}
{{- $title := "" -}}
{{- if hasKey .item "name" -}}
  {{- if or (not (kindIs "string" .item.name)) (not (trim .item.name)) -}}
    {{- fail (printf "alerts[%d].name must be a nonempty string." .index) -}}
  {{- end -}}
  {{- $title = trim .item.name -}}
{{- else -}}
  {{- $alert := fromJson .item.json -}}
  {{- if or (not (kindIs "map" $alert)) (and (hasKey $alert "Error") (eq (len $alert) 1)) -}}
    {{- fail (printf "alerts[%d].json must contain a valid JSON object." .index) -}}
  {{- end -}}
  {{- $jsonTitle := get $alert "title" -}}
  {{- if or (not (kindIs "string" $jsonTitle)) (not (trim $jsonTitle)) -}}
    {{- fail (printf "alerts[%d].json must contain a nonempty title, or set the item name." .index) -}}
  {{- end -}}
  {{- $title = trim $jsonTitle -}}
{{- end -}}
{{- $fullname := include "parseable.fullname" .root -}}
{{- $slug := regexReplaceAll "[^a-z0-9]+" (lower $title) "-" | trimAll "-" -}}
{{- $slug = default "item" $slug | trunc 23 | trimSuffix "-" -}}
{{- $hash := sha256sum (printf "%s/%s" $fullname $title) | trunc 8 -}}
{{- printf "%s-alert-%s-%s" ($fullname | trunc 20 | trimSuffix "-") $slug $hash -}}
{{- end -}}

{{/*
Validate inline dashboard JSON before Helm creates resources or starts the Job.
External ConfigMap content is checked by the Job because Helm cannot read it.
*/}}
{{- define "parseable.validateInlineDashboardJson" -}}
{{- $name := .name -}}
{{- if not (kindIs "string" .json) -}}
  {{- fail (printf "dashboard %q: json must be a JSON string." $name) -}}
{{- end -}}
{{- if not (trim .json) -}}
  {{- fail (printf "dashboard %q: json cannot be empty." $name) -}}
{{- end -}}
{{- if gt (len .json) 900000 -}}
  {{- fail (printf "dashboard %q: inline JSON exceeds 900 KB. Use a separate ConfigMap for this dashboard." $name) -}}
{{- end -}}
{{- $dashboard := fromJson .json -}}
{{- if or (not (kindIs "map" $dashboard)) (and (hasKey $dashboard "Error") (eq (len $dashboard) 1)) -}}
  {{- fail (printf "dashboard %q: invalid JSON. Check the dashboard JSON and try again." $name) -}}
{{- end -}}
{{- if not (kindIs "slice" (get $dashboard "tiles")) -}}
  {{- fail (printf "dashboard %q: json must include tiles as a list." $name) -}}
{{- end -}}
{{- range $index, $tile := get $dashboard "tiles" -}}
  {{- if not (kindIs "map" $tile) -}}
    {{- fail (printf "dashboard %q: tiles[%d] must be a JSON object." $name $index) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "parseable.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Metadata labels attached to every object (no component/selector labels).
*/}}
{{- define "parseable.labels" -}}
helm.sh/chart: {{ include "parseable.chart" . }}
app.kubernetes.io/name: {{ include "parseable.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{/*
Name of the service account to use.
*/}}
{{- define "parseable.serviceAccountName" -}}
{{- if .Values.parseable.serviceAccount.create }}
{{- default (include "parseable.fullname" .) .Values.parseable.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.parseable.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference for the readiness-wait init containers.
*/}}
{{- define "parseable.waitImage" -}}
{{- $w := .Values.parseable.waitImage -}}
{{- printf "%s:%s" $w.repository (toString $w.tag) -}}
{{- end }}

{{/* Reject Enterprise settings placed under OSS-only values. */}}
{{- define "parseable.validateEnterpriseValues" -}}
{{- $p := .Values.parseable -}}
{{- if hasKey $p "license" -}}
  {{- fail "parseable.license is not a chart value; set parseable.enterprise.enabled=true and use parseable.enterprise.license instead" -}}
{{- end -}}
{{- if and (not $p.enterprise.enabled) (or (not (empty $p.enterprise.license.secretName)) (not (empty $p.enterprise.license.dataKey))) -}}
  {{- fail "parseable.enterprise.license requires parseable.enterprise.enabled=true" -}}
{{- end -}}
{{- if and (not $p.enterprise.enabled) (regexMatch "(^|/)parseable-enterprise$" $p.image.repository) -}}
  {{- fail "parseable.image points to an Enterprise image while parseable.enterprise.enabled is false; set parseable.enterprise.enabled=true and use parseable.enterprise.image" -}}
{{- end -}}
{{- end }}

{{/* Enterprise standalone requires a versioned image with P_MODE=all support. */}}
{{- define "parseable.validateEnterpriseStandaloneImage" -}}
{{- $ent := .Values.parseable.enterprise -}}
{{- if and (eq .Values.parseable.deploymentMode "standalone") $ent.enabled -}}
  {{- $tag := $ent.image.tag | default .Chart.AppVersion -}}
  {{- if and (ne $tag "edge") (not (regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+$" $tag)) -}}
    {{- fail (printf "Enterprise standalone requires parseable.enterprise.image.tag v3.2.8 or later; got %q" $tag) -}}
  {{- end -}}
  {{- if and (ne $tag "edge") (not (semverCompare ">=3.2.8" $tag)) -}}
    {{- fail (printf "Enterprise standalone requires parseable.enterprise.image.tag v3.2.8 or later; got %q" $tag) -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/* Validate Enterprise license configuration before rendering workloads. */}}
{{- define "parseable.validateEnterpriseLicense" -}}
{{- $ent := .Values.parseable.enterprise -}}
{{- if $ent.enabled -}}
  {{- $license := $ent.license -}}
  {{- $hasSignature := or (not (empty $license.signature.source)) (not (empty $license.signature.key)) (not (empty $license.signature.base64)) -}}
  {{- $hasLicense := or (not (empty $license.secretName)) (not (empty $license.dataKey)) -}}
  {{- $tag := default .Chart.AppVersion $ent.image.tag -}}
  {{- if and (eq .Values.parseable.deploymentMode "standalone") (or $hasSignature (not (empty $license.mountPath))) -}}
    {{- fail "Enterprise standalone does not support legacy license files or signatures; use the built-in trial or license.secretName and license.dataKey for the license API Job" -}}
  {{- end -}}
  {{- if and (not $hasSignature) (regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+].*)?$" $tag) (semverCompare "<3.2.7" $tag) -}}
    {{- fail (printf "Enterprise image %s requires a legacy license. Set license.secretName, license.dataKey, license.signature.source=file, and license.signature.key." $tag) -}}
  {{- end -}}
  {{- if hasKey $license "datakey" -}}
    {{- fail "Invalid license field 'datakey'. Rename it to 'dataKey', for example: dataKey: parseable_license.json" -}}
  {{- end -}}
  {{- if $hasSignature -}}
    {{- if empty $license.secretName -}}
      {{- fail "License signature is configured, but license.secretName is missing. Set it to the name of the Kubernetes Secret containing the license files." -}}
    {{- end -}}
    {{- if empty $license.dataKey -}}
      {{- fail "License signature is configured, but license.dataKey is missing. Set it to the license data key in that Secret." -}}
    {{- end -}}
    {{- if eq $ent.license.signature.source "file" -}}
      {{- if empty $ent.license.signature.key -}}
        {{- fail "parseable.enterprise.license.signature.source=file requires signature.key" -}}
      {{- end -}}
    {{- else if eq $ent.license.signature.source "base64" -}}
      {{- if or (empty $ent.license.signature.base64.secretName) (empty $ent.license.signature.base64.key) -}}
        {{- fail "parseable.enterprise.license.signature.source=base64 requires signature.base64.secretName and signature.base64.key" -}}
      {{- end -}}
    {{- else -}}
      {{- fail "parseable.enterprise.license.signature requires source=file with key, or source=base64 with base64.secretName and base64.key" -}}
    {{- end -}}
  {{- else if $hasLicense -}}
    {{- if or (empty $ent.license.secretName) (empty $ent.license.dataKey) -}}
      {{- fail "parseable.enterprise.license requires both secretName and dataKey for the license API Job" -}}
    {{- end -}}
  {{- end -}}
  {{- if and (not $hasSignature) (not (empty $ent.license.mountPath)) -}}
    {{- fail "parseable.enterprise.license.mountPath is only used with a legacy signature" -}}
  {{- end -}}
  {{- if not $hasSignature -}}
    {{- if and (not (and (eq .Values.parseable.deploymentMode "standalone") (eq $tag "edge"))) (not (regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+].*)?$" $tag)) -}}
      {{- fail "Cannot verify Enterprise image version for license-free startup: use a versioned image tag (v3.2.7 or newer), or configure a legacy license with signature" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
