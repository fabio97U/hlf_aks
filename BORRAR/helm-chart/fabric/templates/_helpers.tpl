{{- define "fabric.cachaincert" -}}
{{- if not (empty .Values.certificates.caIntermediateTls) }}
{{- .Values.certificates.caIntermediateTls }}
{{- end }}
{{- .Values.certificates.caRootTls }}
{{- end -}}

{{- define "fabric.dockerconfigjson" }}
{{- printf "{\"auths\":{\"%s\":{\"username\":\"%s\",\"password\":\"%s\",\"auth\":\"%s\"}}}" .registry .username .password (printf "%s:%s" .username .password | b64enc) | b64enc }}
{{- end }}

{{- define "fabric.genesissecret" -}}
{{- $secret := lookup "v1" "Secret" "hlf" "hlf-genesis-block" -}}
{{- if $secret -}}
{{ $secret.data.genesisblock }}
{{- else -}}
{{ "empty" | b64enc }}
{{- end -}}
{{- end -}}
