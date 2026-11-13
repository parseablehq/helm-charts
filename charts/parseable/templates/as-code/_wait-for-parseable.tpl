{{/* Wait for the API endpoint before a provisioning Job makes its first request. */}}
{{- define "parseable.waitForApi" -}}
{{- $p := .Values.parseable -}}
{{- $fullname := include "parseable.fullname" . -}}
{{- $target := printf "%s-querier-service" $fullname -}}
{{- if eq $p.deploymentMode "standalone" -}}
  {{- $target = printf "%s-standalone-service" $fullname -}}
{{- else if $p.enterprise.enabled -}}
  {{- $target = printf "%s-prism-service" $fullname -}}
{{- end -}}
{{- $url := printf "http://%s.%s" $target .Release.Namespace -}}
initContainers:
  - name: wait-for-parseable
    image: docker.io/curlimages/curl:latest
    imagePullPolicy: IfNotPresent
    command: ["/bin/sh", "-c"]
    args:
      - |-
        deadline=$(( $(date +%s) + 120 ))
        echo "Waiting for Parseable API at {{ $url }}..."
        until curl -fs --connect-timeout 2 --max-time 3 -o /dev/null "{{ $url }}/api/v1/readiness"; do
          if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "ERROR: Parseable API at {{ $url }} did not become ready within 120 seconds" >&2
            exit 1
          fi
          sleep 5
        done
{{- end -}}
