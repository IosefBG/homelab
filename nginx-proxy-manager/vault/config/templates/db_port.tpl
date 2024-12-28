{{ with secret "test/nginx-proxy-manager/postgres" }}{{ .Data.data.port }}{{ end }}
