{{/* Wait for the API endpoint before a provisioning Job makes its first request. */}}
{{- define "parseable.waitForApi" -}}
{{- $p := .Values.parseable -}}
{{- $fullname := include "parseable.fullname" . -}}
{{- $target := printf "%s-querier-service" $fullname -}}
{{- $port := $p.distributed.querier.service.port -}}
{{- if eq $p.deploymentMode "standalone" -}}
  {{- $target = printf "%s-standalone-service" $fullname -}}
  {{- $port = $p.standalone.service.port -}}
{{- else if $p.enterprise.enabled -}}
  {{- $target = printf "%s-prism-service" $fullname -}}
  {{- $port = $p.distributed.prism.service.port -}}
{{- end -}}
{{- $url := printf "http://%s.%s:%v" $target .Release.Namespace $port -}}
initContainers:
  - name: wait-for-parseable
    image: {{ include "parseable.waitImage" . | quote }}
    imagePullPolicy: {{ $p.waitImage.pullPolicy }}
    command: ["/bin/sh", "-c"]
    args:
      - |-
        deadline=$(( $(date +%s) + 120 ))
        echo "Waiting for Parseable API at {{ $url }}..."
        until curl -fs --connect-timeout 2 --max-time 5 -o /dev/null "{{ $url }}/api/v1/readiness"; do
          if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "ERROR: Parseable API at {{ $url }} did not become ready within 120 seconds" >&2
            exit 1
          fi
          sleep 5
        done
{{- end -}}
