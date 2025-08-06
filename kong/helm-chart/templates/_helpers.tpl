{{/*
Expand the name of the chart.
*/}}
{{- define "kong-gateway-poc.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "kong-gateway-poc.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "kong-gateway-poc.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "kong-gateway-poc.labels" -}}
helm.sh/chart: {{ include "kong-gateway-poc.chart" . }}
{{ include "kong-gateway-poc.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "kong-gateway-poc.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kong-gateway-poc.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Generate route plugins list for annotations
*/}}
{{- define "kong-gateway-poc.routePlugins" -}}
{{- if . }}
{{- . | join "," }}
{{- end }}
{{- end }}

{{/*
Generate route description for comments
*/}}
{{- define "kong-gateway-poc.routeDescription" -}}
{{- if . }}
# {{ . }}
{{- end }}
{{- end }}