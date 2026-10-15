{{/* Give a useful error for invalid retention durations before the Job is created. */}}
{{- define "parseable.validateRetentionDuration" -}}
{{- $duration := printf "%v" .duration -}}
{{- if or (eq $duration "") (eq $duration "0d") -}}
{{- /* An explicit empty value or 0d removes the existing retention rules. */ -}}
{{- else if not (hasSuffix "d" $duration) -}}
{{- fail (printf "dataset %s: retention.durationDays must end with 'd' (e.g. 10d)" .name) -}}
{{- else if not (regexMatch "^[1-9][0-9]*d$" $duration) -}}
{{- fail (printf "dataset %s: retention.durationDays must be a positive whole number of days (e.g. 10d)" .name) -}}
{{- else -}}
{{- $digits := trimSuffix "d" $duration -}}
{{- if or (gt (len $digits) 4) (gt (atoi $digits) 3650) -}}
{{- fail (printf "dataset %s: retention.durationDays must be between 1d and 3650d" .name) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Validate per-dataset Smart Cache sizes before the Job is created. */}}
{{- define "parseable.validateSmartCacheSize" -}}
{{- $size := printf "%v" .size -}}
{{- if or (eq $size "") (eq $size "0Gi") -}}
{{- /* An explicit empty value or 0Gi removes the dataset Smart Cache. */ -}}
{{- else if not (hasSuffix "Gi" $size) -}}
{{- fail (printf "dataset %s: smartCache.size must end with 'Gi' (e.g. 10Gi)" .name) -}}
{{- else if not (regexMatch "^[1-9][0-9]*Gi$" $size) -}}
{{- fail (printf "dataset %s: smartCache.size must be a positive whole number of Gi (e.g. 10Gi)" .name) -}}
{{- else -}}
{{- $digits := trimSuffix "Gi" $size -}}
{{- if gt (len $digits) 9 -}}
{{- fail (printf "dataset %s: smartCache.size must not exceed 999999999Gi" .name) -}}
{{- else if lt (atoi $digits) 10 -}}
{{- fail (printf "dataset %s: smartCache.size must be at least 10Gi" .name) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Match Parseable's stream-name rules before interpolating a name into Job URLs. */}}
{{- define "parseable.validateDatasetName" -}}
{{- $name := . -}}
{{- if not (regexMatch "^[\\p{L}\\p{N}_-]+$" $name) -}}
  {{- fail (printf "dataset name %q is invalid: use letters, digits, '-' or '_' without spaces (e.g. payment-logs)" $name) -}}
{{- end -}}
{{- if has $name (list "select" "from" "where" "group" "by" "order" "limit" "offset" "join" "and" "sql") -}}
  {{- fail (printf "dataset name %q is invalid: SQL keywords cannot be dataset names; choose another name" $name) -}}
{{- end -}}
{{- if eq $name "DEFAULT_TENANT" -}}
  {{- fail (printf "dataset name %q is reserved; choose another name" $name) -}}
{{- end -}}
{{- end -}}

{{/* Keep cross-field dataset errors readable; JSON Schema's allOf output hides the rule. */}}
{{- define "parseable.validateDatasetCombination" -}}
{{- $ds := .dataset -}}
{{- $source := $ds.logSource -}}
{{- $type := $ds.telemetryType -}}
{{- if has "agent-observability" (default (list) $ds.tags) -}}
  {{- if or (ne $source "otel-traces") (ne $type "traces") -}}
    {{- fail (printf "dataset %q: tag agent-observability requires logSource: otel-traces and telemetryType: traces (got logSource: %s, telemetryType: %s)" $ds.name $source $type) -}}
  {{- end -}}
{{- end -}}

{{- $required := dict "otel-logs" "logs" "otel-metrics" "metrics" "otel-traces" "traces" -}}
{{- if and (hasKey $required $source) (ne $type (get $required $source)) -}}
  {{- fail (printf "dataset %q: logSource: %s requires telemetryType: %s (got %s)" $ds.name $source (get $required $source) $type) -}}
{{- end -}}
{{- if and (hasKey $ds "smartCache") (not .enterpriseEnabled) -}}
  {{- fail (printf "dataset %q: smartCache requires parseable.enterprise.enabled: true" $ds.name) -}}
{{- end -}}
{{- end -}}

{{/* Validate references when this release explicitly declares roles. */}}
{{- define "parseable.validateRoleReferences" -}}
{{- $known := list -}}
{{- range $role := .roles -}}
  {{- $known = append $known $role.name -}}
{{- end -}}
{{- range $item := .items -}}
  {{- range $role := $item.roles -}}
    {{- if not (has $role $known) -}}
      {{- fail (printf "%s %q: role %q is not listed in parseable.roles; available: %s. Fix the name or add that role" $.kind $item.name $role (join ", " $known | default "(none)")) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
