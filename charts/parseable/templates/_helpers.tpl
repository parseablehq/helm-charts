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

{{/* Validate license-free startup only for Enterprise distributed deployments. */}}
{{- define "parseable.validateEnterpriseLicense" -}}
{{- $ent := .Values.parseable.enterprise -}}
{{- if and (eq .Values.parseable.deploymentMode "distributed") $ent.enabled (not $ent.license.enabled) -}}
  {{- if empty $ent.image.tag -}}
    {{- fail "parseable.enterprise.license.enabled=false requires an explicit Enterprise image tag that supports the built-in default license" -}}
  {{- end -}}
  {{- if regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+" $ent.image.tag -}}
    {{- if semverCompare "<=3.2.6" (regexFind "^v?[0-9]+\\.[0-9]+\\.[0-9]+" $ent.image.tag) -}}
      {{- fail "Enterprise image tags v3.2.6 and older require a license Secret; use a newer image or set parseable.enterprise.license.enabled=true" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
