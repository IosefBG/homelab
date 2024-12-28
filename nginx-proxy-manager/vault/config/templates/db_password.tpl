{{ with secret "test/nginx-proxy-manager/postgres" }}{{ .Data.data.password }}{{ end }}
