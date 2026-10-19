#!/bin/bash
# Harbor 自签证书生成脚本（在 B 机 192.168.80.20 上运行）
# 用途：为域名 harbor.local 生成 CA 根证书 + 服务器证书
# 产物目录：/usr/local/harbor/cert/
#   ca.key / ca.crt            -> CA 根证书（ca.crt 要拷到 A/C/D 客户端）
#   harbor.local.key / .csr / .crt -> 服务器证书（harbor.yml 指向这两个）
#
# 关键：docker/客户端校验要求证书带 SAN(SubjectAltName)=DNS:harbor.local，
#       没这个字段会报 x509: certificate is valid for ... not harbor.local

set -e
CERT_DIR=/usr/local/harbor/cert
DOMAIN=harbor.local
DAYS=3650

mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo "== 1/4 生成 CA 私钥 + 自签 CA 根证书 =="
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -sha512 -days "$DAYS" \
  -subj "/C=CN/ST=Hubei/L=Wuhan/O=local/CN=$DOMAIN" \
  -key ca.key -out ca.crt

echo "== 2/4 生成服务器私钥 + 证书请求(CSR) =="
openssl genrsa -out "$DOMAIN.key" 4096
openssl req -sha512 -new \
  -subj "/C=CN/ST=Hubei/L=Wuhan/O=local/CN=$DOMAIN" \
  -key "$DOMAIN.key" -out "$DOMAIN.csr"

echo "== 3/4 写 SAN 扩展文件（docker 强制要求） =="
cat > v3.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:$DOMAIN
EOF

echo "== 4/4 用 CA 签发服务器证书 =="
openssl x509 -req -sha512 -days "$DAYS" \
  -extfile v3.ext -CA ca.crt -CAkey ca.key -CAcreateserial \
  -in "$DOMAIN.csr" -out "$DOMAIN.crt"

echo "== 完成，目录内容： =="
ls -1 "$CERT_DIR"
echo
echo "下一步：把 ca.crt 拷到 A/C/D 的 /etc/docker/certs.d/harbor.local/ 下"
