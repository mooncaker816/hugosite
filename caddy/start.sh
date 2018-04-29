#!/bin/bash

docker run -d --name=mycaddy --rm \
    -e "ACME_AGREE=true" \
    -e "SECRET=xxxxxx" \
    -e "CADDYPATH=/etc/caddycerts" \
    -v ~/.ssh/id_rsa:/home/.ssh/id_rsa \
    -v $(pwd)/Caddyfile:/etc/Caddyfile \
    -v $HOME/.caddy:/etc/caddycerts \
    -v /var/log/caddy:/var/log/caddy \
    -p 80:80 -p 443:443 \
    mooncaker816/caddy-hugo