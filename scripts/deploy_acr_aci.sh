#!/usr/bin/env bash
# ============================================================================
# SCRIPT DE DEPLOY VIA AZURE CLI - ACR + ACI + ORACLE DATABASE (FIAP)
# Aplicação containerizada Non-Root no ACI conectada ao Oracle Database da FIAP
# Nenhuma credencial fica no código: todas são lidas de variáveis de ambiente
# ============================================================================
#
# Uso:
#   export DB_USER="rm561279"              # usuário Oracle FIAP (RM)
#   export DB_PASS="********"              # senha Oracle FIAP
#   export JWT_SECRET="$(openssl rand -base64 48)"
#   export DEMO_PASSWORD="********"        # senha das contas de demonstração
#   ./deploy_acr_aci.sh
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# 1. VARIÁVEIS DE CONFIGURAÇÃO DO AMBIENTE
# ----------------------------------------------------------------------------
: "${DB_USER:?Defina DB_USER (usuário Oracle FIAP)}"
: "${DB_PASS:?Defina DB_PASS (senha Oracle FIAP)}"
: "${JWT_SECRET:?Defina JWT_SECRET (mínimo 32 caracteres)}"
: "${DEMO_PASSWORD:?Defina DEMO_PASSWORD (senha das contas de demonstração)}"

DB_URL="${DB_URL:-jdbc:oracle:thin:@oracle.fiap.com.br:1521:ORCL}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-clyvovet-fiap}"
LOCATION="${LOCATION:-brazilsouth}"
ACR_NAME="${ACR_NAME:-acrclyvovet${RANDOM}}"
ACI_APP_NAME="aci-clyvovet-app"
IMAGE_NAME="clyvovet-api"
IMAGE_TAG="${IMAGE_TAG:-v2.0.0}"
DNS_NAME_APP="${DNS_NAME_APP:-clyvovet-app-${RANDOM}}"

echo "========================================================================"
echo ">> INICIANDO DEPLOY AUTOMATIZADO CLYVO VET NO AZURE (ACR + ACI + ORACLE)"
echo ">> Resource Group: $RESOURCE_GROUP | Location: $LOCATION"
echo "========================================================================"

# ----------------------------------------------------------------------------
# 2. CRIAÇÃO DO GRUPO DE RECURSOS (RESOURCE GROUP)
# ----------------------------------------------------------------------------
echo ">> 1. Criando Resource Group na Azure..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION"

# ----------------------------------------------------------------------------
# 3. CRIAÇÃO DO AZURE CONTAINER REGISTRY (ACR)
# ----------------------------------------------------------------------------
echo ">> 2. Criando Azure Container Registry ($ACR_NAME)..."
az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Basic \
  --admin-enabled true

ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer --output tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" --output tsv)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ----------------------------------------------------------------------------
# 4. BUILD DA IMAGEM DOCKER (NON-ROOT) DIRETAMENTE NO ACR
# O build roda na Azure (linux/amd64), evitando incompatibilidade com Macs ARM
# ----------------------------------------------------------------------------
echo ">> 3. Construindo a imagem Java 21 Non-Root no ACR..."
az acr build \
  --registry "$ACR_NAME" \
  --image "$IMAGE_NAME:$IMAGE_TAG" \
  --platform linux/amd64 \
  --file "$REPO_ROOT/Dockerfile" \
  "$REPO_ROOT"

# ----------------------------------------------------------------------------
# 5. DEPLOY DA APLICAÇÃO SPRING BOOT NO AZURE CONTAINER INSTANCES (ACI)
# ----------------------------------------------------------------------------
echo ">> 4. Provisionando Container da Aplicação no Azure Container Instances..."
az container create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACI_APP_NAME" \
  --image "$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG" \
  --registry-login-server "$ACR_LOGIN_SERVER" \
  --registry-username "$ACR_NAME" \
  --registry-password "$ACR_PASSWORD" \
  --os-type Linux \
  --cpu 1 \
  --memory 2.0 \
  --ports 8080 \
  --ip-address Public \
  --dns-name-label "$DNS_NAME_APP" \
  --restart-policy Always \
  --environment-variables \
      SPRING_PROFILES_ACTIVE="prod,demo" \
      SERVER_PORT="8080" \
  --secure-environment-variables \
      DB_URL="$DB_URL" \
      DB_USER="$DB_USER" \
      DB_PASS="$DB_PASS" \
      JWT_SECRET="$JWT_SECRET" \
      DEMO_PASSWORD="$DEMO_PASSWORD"

# ----------------------------------------------------------------------------
# 6. EVIDÊNCIAS E TESTES DE ACESSO
# ----------------------------------------------------------------------------
APP_FQDN=$(az container show --resource-group "$RESOURCE_GROUP" --name "$ACI_APP_NAME" --query "ipAddress.fqdn" --output tsv)

echo ">> Aguardando a aplicação responder (Flyway + Spring Boot)..."
for _ in $(seq 1 40); do
  if curl -s -o /dev/null -f "http://$APP_FQDN:8080/web/login"; then break; fi
  sleep 6
done

echo "========================================================================"
echo ">> DEPLOY CONCLUÍDO!"
echo ">> URL da Aplicação Web: http://$APP_FQDN:8080/"
echo ">> URL do Swagger UI:   http://$APP_FQDN:8080/swagger-ui.html"
echo ">> Logs do container:   az container logs -g $RESOURCE_GROUP -n $ACI_APP_NAME"
echo "========================================================================"
