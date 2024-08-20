# registry

## source
https://github.com/distribution/distribution/blob/main/README.md

## docs
https://distribution.github.io/distribution/

## install
```
wget -qO- https://github.com/distribution/distribution/releases/download/v2.8.3/registry_2.8.3_linux_amd64.tar.gz | tar -xzf - registry && mv registry /usr/local/bin/
```

## certificate
path /etc/distribution/generate_cert.sh
```bash
#!/bin/bash

# create config.cnf
cat - > config.cnf << EOF_CONFIG
[ req ]
prompt = no
distinguished_name = distinguished_name
x509_extensions = x509_extension
[ distinguished_name ]
CN = localhost
[ x509_extension ]
subjectAltName = DNS:localhost, IP:127.0.0.1, IP:192.168.178.59
extendedKeyUsage = critical, serverAuth, clientAuth
keyUsage = critical, digitalSignature, keyEncipherment
EOF_CONFIG

# create self signed certificate
openssl req -x509 -config config.cnf -newkey rsa:2048 -keyout localhost.key -out localhost.crt -nodes

# add certificate to trusted list
cp localhost.crt /usr/local/share/ca-certificates/
update-ca-certificates
```

## htpasswd
create password for user admin
```
apt install apache2-utils
htpasswd -b -c -B /etc/distribution/htpasswd admin 123456
```

## config
path /etc/distribution/config.yml
```yml
version: 0.1

log:
  accesslog:
    disabled: false
  level: info
  fields:
    service: registry

storage:
  delete:
    enabled: true
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
    maxthreads: 100

http:
  addr: :5000
  secret: asecretforlocaldevelopment
  tls:
    certificate: /etc/distribution/localhost.crt
    key: /etc/distribution/localhost.key
  debug:
    addr: :5001
    prometheus:
      enabled: true
      path: /metrics
  headers:
    X-Content-Type-Options: [nosniff]
  http2:
    disabled: false
  h2c:
    enabled: false

auth:
  htpasswd:
    realm: basic-realm
    path: /etc/distribution/htpasswd
```

## service
path /etc/systemd/system/registry.service
```ini
[Unit]
Description=registry
After=network.service

[Service]
Type=simple
Restart=always
ExecStart=/usr/local/bin/registry serve /etc/distribution/config.yml

[Install]
WantedBy=default.target
RequiredBy=network.target
```

## test
```bash
# enable and start registry service
systemctl enable registry
systemctl start registry
systemctl status registry

# get image catalog from registry
curl --user admin:123456 https://localhost:5000/v2/_catalog

# pull push image with podman
podman pull docker.io/rancher/cowsay:latest
podman tag docker.io/rancher/cowsay:latest localhost:5000/rancher/cowsay:latest
podman login -u admin -p 123456 localhost:5000
podman push localhost:5000/rancher/cowsay:latest
podman run localhost:5000/rancher/cowsay:latest Mooo
 ______
< Mooo >
 ------
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||

```

# loadbalancer (haproxy)

## source
https://github.com/haproxy/haproxy

## docs
https://www.haproxy.com/documentation/haproxy-configuration-tutorials/load-balancing/tcp/

## install
```bash
apt install haproxy
```

## config
path /etc/haproxy/haproxy.cfg
```ini
global
        log /dev/log    local0
        log /dev/log    local1 notice
        chroot /var/lib/haproxy
        stats socket /run/haproxy/admin.sock mode 660 level admin
        stats timeout 30s
        user haproxy
        group haproxy
        daemon

        # Default SSL material locations
        ca-base /etc/ssl/certs
        crt-base /etc/ssl/private

        # See: https://ssl-config.mozilla.org/#server=haproxy&server-version=2.0.3&config=intermediate
        ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
        ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256
        ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
        log     global
        mode    http
        #option  httplog
        option  dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
        errorfile 400 /etc/haproxy/errors/400.http
        errorfile 403 /etc/haproxy/errors/403.http
        errorfile 408 /etc/haproxy/errors/408.http
        errorfile 500 /etc/haproxy/errors/500.http
        errorfile 502 /etc/haproxy/errors/502.http
        errorfile 503 /etc/haproxy/errors/503.http
        errorfile 504 /etc/haproxy/errors/504.http

frontend registry
        mode tcp
        bind :5005
        default_backend registry

backend registry
        mode tcp
        balance leastconn
        server registry1 10.2.10.205:5000
```

## test
```bash
# enable and start registry service
systemctl restart haproxy
systemctl status haproxy

# get image catalog from registry
curl --user admin:123456 https://localhost:5005/v2/_catalog

# pull push image with podman
podman pull docker.io/beezu/cmatrix:latest
podman tag docker.io/beezu/cmatrix:latest localhost:5005/beezu/cmatrix:latest
podman login -u admin -p 123456 localhost:5005
podman push localhost:5005/beezu/cmatrix:latest
podman run --rm --log-driver none -it localhost:5005/beezu/cmatrix:latest
```
