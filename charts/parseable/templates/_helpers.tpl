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

{{/* Validate Enterprise license configuration before rendering workloads. */}}
{{- define "parseable.validateEnterpriseLicense" -}}
{{- $ent := .Values.parseable.enterprise -}}
{{- if and (eq .Values.parseable.deploymentMode "distributed") $ent.enabled -}}
  {{- $license := $ent.license -}}
  {{- $hasSignature := or (not (empty $license.signature.source)) (not (empty $license.signature.key)) (not (empty $license.signature.base64)) -}}
  {{- $hasLicense := or (not (empty $license.secretName)) (not (empty $license.dataKey)) -}}
  {{- $tag := default .Chart.AppVersion $ent.image.tag -}}
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
    {{- if not (regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+(?:[-+].*)?$" $tag) -}}
      {{- fail "Cannot verify Enterprise image version for license-free startup: use a versioned image tag (v3.2.7 or newer), or configure a legacy license with signature" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
