{{- define "podinfo.selectorLabels" -}}
app.kubernetes.io/name: podinfo
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "podinfo.labels" -}}
{{ include "podinfo.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* CI always passes a digest. tag is only there for helm lint / local tries. */}}
{{- define "podinfo.image" -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}@{{ .Values.image.digest }}
{{- else if .Values.image.tag -}}
{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- else -}}
{{ fail "set image.digest or image.tag" }}
{{- end -}}
{{- end }}
