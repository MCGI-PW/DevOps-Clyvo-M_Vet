#!/usr/bin/env bash
# ============================================================================
# HTTPS + LOGIN SOCIAL (OAUTH2) NO AZURE CONTAINER INSTANCES
# Recria o container group com dois containers:
#   - app   : a API Clyvo Vet (imagem já publicada no ACR), só na porta interna 8080
#   - caddy : proxy reverso que emite o certificado HTTPS (Let's Encrypt) para o
#             FQDN do ACI e redireciona HTTP -> HTTPS
# O Google só aceita destino de login OAuth2 em HTTPS (exceto localhost).
#
# Uso (as credenciais são pedidas sem aparecer na tela):
#   ./scripts/deploy_https_oauth.sh
# ============================================================================

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-clyvovet-fiap}"
LOCATION="${LOCATION:-brazilsouth}"
ACR_NAME="${ACR_NAME:-acrclyvovet23613}"
ACI_APP_NAME="${ACI_APP_NAME:-aci-clyvovet-app}"
DNS_NAME_APP="${DNS_NAME_APP:-clyvovet-app-16666}"
IMAGE="${ACR_NAME}.azurecr.io/clyvovet-api:${IMAGE_TAG:-v2.0.0}"
CADDY_IMAGE="${ACR_NAME}.azurecr.io/caddy:2.8.4"
FQDN="${DNS_NAME_APP}.${LOCATION}.azurecontainer.io"
DB_URL="${DB_URL:-jdbc:oracle:thin:@oracle.fiap.com.br:1521:ORCL}"

perguntar() { # nome, texto, oculto(0/1)
  local valor
  if [ "$3" = "1" ]; then read -rsp "$2: " valor; echo; else read -rp "$2: " valor; fi
  printf -v "$1" '%s' "$valor"
}

perguntar DB_USER "Usuário do Oracle FIAP, com o rm [rm561279]" 0
DB_USER="${DB_USER:-rm561279}"
case "$DB_USER" in rm*|RM*) ;; *) DB_USER="rm${DB_USER}";; esac
perguntar DB_PASS "Senha do Oracle FIAP" 1
perguntar DEMO_PASSWORD "Senha das contas demo [senha123]" 1
DEMO_PASSWORD="${DEMO_PASSWORD:-senha123}"
perguntar GOOGLE_CLIENT_ID "Google Client ID (Enter para pular)" 0
perguntar GOOGLE_CLIENT_SECRET "Google Client Secret (Enter para pular)" 1
perguntar GITHUB_CLIENT_ID "GitHub Client ID (Enter para pular)" 0
perguntar GITHUB_CLIENT_SECRET "GitHub Client Secret (Enter para pular)" 1

ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" --output tsv)
JWT_SECRET=$(openssl rand -base64 48)

# O YAML leva segredos: fica num arquivo temporário legível só pelo usuário e é apagado no fim
YAML=$(mktemp)
chmod 600 "$YAML"
trap 'rm -f "$YAML"' EXIT

secure_env() { # nome, valor (variáveis vazias não entram)
  local aspa="'"
  # Em YAML, a aspa simples dentro de '...' é escrita dobrada
  [ -n "$2" ] && printf "        - name: %s\n          secureValue: '%s'\n" "$1" "${2//$aspa/$aspa$aspa}"
  return 0
}

{
cat <<EOF
apiVersion: '2021-10-01'
location: ${LOCATION}
name: ${ACI_APP_NAME}
type: Microsoft.ContainerInstance/containerGroups
properties:
  osType: Linux
  restartPolicy: Always
  imageRegistryCredentials:
    - server: ${ACR_NAME}.azurecr.io
      username: ${ACR_NAME}
      password: '${ACR_PASSWORD}'
  ipAddress:
    type: Public
    dnsNameLabel: ${DNS_NAME_APP}
    ports:
      - {protocol: TCP, port: 80}
      - {protocol: TCP, port: 443}
  containers:
    - name: app
      properties:
        image: ${IMAGE}
        resources: {requests: {cpu: 1.0, memoryInGB: 1.5}}
        ports: [{port: 8080}]
        environmentVariables:
        - name: SPRING_PROFILES_ACTIVE
          value: prod,demo
        - name: SERVER_PORT
          value: '8080'
EOF
secure_env DB_URL "$DB_URL"
secure_env DB_USER "$DB_USER"
secure_env DB_PASS "$DB_PASS"
secure_env JWT_SECRET "$JWT_SECRET"
secure_env DEMO_PASSWORD "$DEMO_PASSWORD"
secure_env GOOGLE_CLIENT_ID "$GOOGLE_CLIENT_ID"
secure_env GOOGLE_CLIENT_SECRET "$GOOGLE_CLIENT_SECRET"
secure_env GITHUB_CLIENT_ID "$GITHUB_CLIENT_ID"
secure_env GITHUB_CLIENT_SECRET "$GITHUB_CLIENT_SECRET"
cat <<EOF
    - name: caddy
      properties:
        image: ${CADDY_IMAGE}
        command: [caddy, reverse-proxy, --from, '${FQDN}', --to, 'localhost:8080']
        resources: {requests: {cpu: 0.5, memoryInGB: 0.5}}
        ports: [{port: 80}, {port: 443}]
EOF
} > "$YAML"

echo ">> Recriando o container group com HTTPS..."
az container delete --resource-group "$RESOURCE_GROUP" --name "$ACI_APP_NAME" --yes --output none 2>/dev/null || true
az container create --resource-group "$RESOURCE_GROUP" --file "$YAML" --output none

echo ">> Aguardando o certificado HTTPS e a aplicação..."
for _ in $(seq 1 50); do
  if curl -s -o /dev/null -f "https://${FQDN}/web/login"; then
    echo "========================================================================"
    echo ">> NO AR COM HTTPS: https://${FQDN}/"
    echo ">> Swagger:         https://${FQDN}/swagger-ui.html"
    echo "========================================================================"
    exit 0
  fi
  sleep 6
done
echo ">> Ainda não respondeu em HTTPS. Logs:"
echo "   az container logs -g ${RESOURCE_GROUP} -n ${ACI_APP_NAME} --container-name app"
echo "   az container logs -g ${RESOURCE_GROUP} -n ${ACI_APP_NAME} --container-name caddy"
exit 1
