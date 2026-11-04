#!/usr/bin/env bash
# ============================================================================
# HTTPS + LOGIN SOCIAL (OAUTH2) + IA NO AZURE CONTAINER INSTANCES
# Recria o container group com três containers:
#   - app         : a API Aurora Pet (imagem já publicada no ACR), só na porta interna 8080
#   - aurorascribe: o serviço de IA AuroraScribe (repositório IoT-Clyvo-Vet_M), só na porta interna 8000;
#                   a API chama em http://localhost:8000 (mesmo grupo, mesma rede)
#   - caddy       : proxy reverso que emite o certificado HTTPS (Let's Encrypt) para o
#                   FQDN do ACI e redireciona HTTP -> HTTPS. O certificado fica num
#                   compartilhamento do Azure Files (/data), para sobreviver a reinícios:
#                   o Let's Encrypt emite no máximo 5 certificados por semana para o mesmo endereço
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
IMAGE="${ACR_NAME}.azurecr.io/clyvovet-api:${IMAGE_TAG:-v2.2.0}"
CADDY_IMAGE="${ACR_NAME}.azurecr.io/caddy:2.8.4"
SCRIBE_IMAGE="${ACR_NAME}.azurecr.io/clyvoscribe:${SCRIBE_TAG:-v1.2.0}"
FQDN="${DNS_NAME_APP}.${LOCATION}.azurecontainer.io"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stclyvovet23613}"
CADDY_SHARE="caddy-data"
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
perguntar DB_PASS_CONFIRMACAO "Repita a senha do Oracle FIAP" 1
# Senha errada derruba o container em loop, e cada reinício é uma tentativa de login que pode bloquear a conta no Oracle
if [ -z "$DB_PASS" ] || [ "$DB_PASS" != "$DB_PASS_CONFIRMACAO" ]; then
  echo ">> As senhas do Oracle não conferem. Nada foi alterado no Azure." >&2
  exit 1
fi
perguntar DEMO_PASSWORD "Senha das contas demo [senha123]" 1
DEMO_PASSWORD="${DEMO_PASSWORD:-senha123}"
# Client IDs são públicos (aparecem na URL de login); só os segredos precisam ser digitados
GOOGLE_ID_PADRAO="458257025008-6nh0adros9fkihvon1f67q3msi0ekgoj.apps.googleusercontent.com"
GITHUB_ID_PADRAO="Ov23liX3g8dkWqvR00Qr"
perguntar GOOGLE_CLIENT_ID "Google Client ID [Enter usa o do projeto]" 0
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-$GOOGLE_ID_PADRAO}"
perguntar GOOGLE_CLIENT_SECRET "Google Client Secret (cole e tecle Enter; não aparece na tela)" 1
perguntar GITHUB_CLIENT_ID "GitHub Client ID [Enter usa o do projeto]" 0
GITHUB_CLIENT_ID="${GITHUB_CLIENT_ID:-$GITHUB_ID_PADRAO}"
perguntar GITHUB_CLIENT_SECRET "GitHub Client Secret (cole e tecle Enter; não aparece na tela)" 1
# Opcional: sem a chave, o AuroraScribe usa o extrator local, sem internet
perguntar ANTHROPIC_API_KEY "Chave do Claude para o AuroraScribe (opcional, Enter pula; não aparece na tela)" 1
echo ">> Recebido: Google secret com ${#GOOGLE_CLIENT_SECRET} caracteres, GitHub secret com ${#GITHUB_CLIENT_SECRET} caracteres, chave do Claude com ${#ANTHROPIC_API_KEY} caracteres."

for provedor in GOOGLE GITHUB; do
  id_var="${provedor}_CLIENT_ID"; secret_var="${provedor}_CLIENT_SECRET"
  if [ -z "${!id_var}" ] || [ -z "${!secret_var}" ]; then
    echo ">> Atenção: sem ${provedor}_CLIENT_ID e ${provedor}_CLIENT_SECRET, o botão de login desse provedor não aparece."
  fi
done
read -rp ">> Continuar com o deploy? [s/N] " continuar
[ "$continuar" = "s" ] || [ "$continuar" = "S" ] || { echo ">> Cancelado. Nada foi alterado no Azure."; exit 1; }

ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" --output tsv)
JWT_SECRET=$(openssl rand -base64 48)

# Armazenamento persistente do certificado HTTPS (criado só na primeira vez)
if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo ">> Criando a conta de armazenamento ${STORAGE_ACCOUNT} para o certificado HTTPS..."
  az storage account create --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --location "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 --output none
fi
az storage share-rm create --storage-account "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" \
  --name "$CADDY_SHARE" --quota 1 --output none 2>/dev/null || true
STORAGE_KEY=$(az storage account keys list --account-name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query "[0].value" --output tsv)

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
  volumes:
    - name: caddy-data
      azureFile:
        shareName: ${CADDY_SHARE}
        storageAccountName: ${STORAGE_ACCOUNT}
        storageAccountKey: '${STORAGE_KEY}'
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
        - name: AURORASCRIBE_URL
          value: http://localhost:8000
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
    - name: aurorascribe
      properties:
        image: ${SCRIBE_IMAGE}
        resources: {requests: {cpu: 0.5, memoryInGB: 0.5}}
        ports: [{port: 8000}]
        environmentVariables:
        - name: CLYVO_IA_MODEL
          value: claude-opus-5-5
EOF
secure_env ANTHROPIC_API_KEY "$ANTHROPIC_API_KEY"
cat <<EOF
    - name: caddy
      properties:
        image: ${CADDY_IMAGE}
        command: [caddy, reverse-proxy, --from, '${FQDN}', --to, 'localhost:8080']
        resources: {requests: {cpu: 0.5, memoryInGB: 0.5}}
        ports: [{port: 80}, {port: 443}]
        volumeMounts: [{name: caddy-data, mountPath: /data}]
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
echo "   az container logs -g ${RESOURCE_GROUP} -n ${ACI_APP_NAME} --container-name aurorascribe"
exit 1
