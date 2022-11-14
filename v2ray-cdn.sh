#!/bin/bash

clear

read -p "Please enter your Domain Name A Record: " DOMAIN
read -p "Please enter vmess Port: " MPORT
read -p "Please enter vless Port: " LPORT

apt remove docker docker-engine docker.io containerd runc
apt update
apt install ca-certificates curl socat gnupg lsb-release -y
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install docker-ce docker-ce-cli containerd.io docker-compose docker-compose-plugin -y

mkdir v2ray
cd v2ray
mkdir tls

curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --register-account -m linuxmaster14@gmail.com
~/.acme.sh/acme.sh --issue -d $DOMAIN --standalone
~/.acme.sh/acme.sh --installcert -d $DOMAIN --key-file ./tls/private.key --fullchain-file ./tls/cert.crt

UUID=$(cat /proc/sys/kernel/random/uuid)

cat > vmess.json << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $MPORT,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/v2fly/tls/cert.crt",
              "keyFile": "/etc/v2fly/tls/private.key"
            }
          ]
        }
      }
      }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

cat > vless.json << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $LPORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0,
            "email": "linuxmaster14@gmail.com"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 80
          },
          {
            "path": "/",
            "dest": 1234,
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "alpn": [
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/v2fly/tls/cert.crt",
              "keyFile": "/etc/v2fly/tls/private.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

cat > docker-compose.yml << EOF
version: "3"

services:
  v2fly_vmess:
    image: v2fly/v2fly-core
    container_name: v2fly_vmess
    restart: always
    ports:
      - "$MPORT:$MPORT"
    volumes:
      - ./vmess.json:/etc/v2fly/config.json
      - ./tls:/etc/v2fly/tls
    command: run -c /etc/v2fly/config.json

  v2fly_vless:
    image: v2fly/v2fly-core
    container_name: v2fly_vless
    restart: always
    ports:
      - "$LPORT:$LPORT"
    volumes:
      - ./vless.json:/etc/v2fly/config.json
      - ./tls:/etc/v2fly/tls
    command: run -c /etc/v2fly/config.json

EOF

docker-compose up -d

vmess_url="vmess://$(echo -n "\
{\
\"v\": \"2\",\
\"ps\": \"${DOMAIN}\",\
\"add\": \"${DOMAIN}\",\
\"port\": \"${MPORT}\",\
\"id\": \"${UUID}\",\
\"aid\": \"0\",\
\"net\": \"ws\",\
\"type\": \"none\",\
\"host\": \"${DOMAIN}\",\
\"tls\": \"tls\"\
}"\
    | base64 -w 0)"

vless_url="vless://$UUID@$DOMAIN:$LPORT?path=/&security=tls&encryption=none&type=ws#$DOMAIN"

clear

echo ""
echo -e "VMESS URL: ${vmess_url}"
echo ""
echo -e "VLESS URL: ${vless_url}"
