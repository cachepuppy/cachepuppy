{{/*
Expand the name of the chart.
*/}}
{{- define "cachepuppy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "cachepuppy.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "cachepuppy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}

{{/*
Kubernetes namespace for this release (set with --namespace on install).
*/}}
{{- define "cachepuppy.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Selector labels shared by workloads and services.
*/}}
{{- define "cachepuppy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cachepuppy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app: cachepuppy-core
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "cachepuppy.labels" -}}
helm.sh/chart: {{ include "cachepuppy.chart" . }}
{{ include "cachepuppy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
cachepuppy.io/tenant-id: {{ default .Release.Namespace .Values.tenant.id | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "cachepuppy.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "cachepuppy.configMapName" -}}
{{- print "cachepuppy-config" -}}
{{- end }}

{{- define "cachepuppy.secretName" -}}
{{- .Values.secrets.existingSecret | default "cachepuppy-secrets" -}}
{{- end }}

{{- define "cachepuppy.headlessServiceName" -}}
{{- print "cachepuppy-headless" -}}
{{- end }}

{{- define "cachepuppy.publicServiceName" -}}
{{- print "cachepuppy-public" -}}
{{- end }}
