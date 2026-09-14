#!/usr/bin/env bash
# ============================================================================
# SCRIPT DE DEPLOY VIA AZURE CLI - OPÇÃO 1: ACR + ACI
# Solução Containerizada Completa (App Non-Root + Banco em Container na Nuvem)
# Cumpre os Requisitos 8.1, 8.2, 8.3, 8.4 e Critérios de Avaliação DevOps FIAP
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# 1. VARIÁVEIS DE CONFIGURAÇÃO DO AMBIENTE
# ----------------------------------------------------------------------------
RESOURCE_GROUP="rg-clyvovet-fiap"
LOCATION="eastus"
ACR_NAME="acrclyvovet${RANDOM}"
ACI_DB_NAME="aci-clyvovet-db"
ACI_APP_NAME="aci-clyvovet-app"
IMAGE_NAME="clyvovet-api"
IMAGE_TAG="v1.0.0"
DNS_NAME_APP="clyvovet-app-${RANDOM}"
DNS_NAME_DB="clyvovet-db-${RANDOM}"

# Credenciais seguras do Banco de Dados
DB_NAME="clyvovet"
DB_USER="clyvouser"
DB_PASS="ClyvoSecPass2026!"
JWT_SECRET="clyvo_secret_key_ultra_secure_minimum_32_chars_2026_devops"

echo "========================================================================"
echo ">> INICIANDO DEPLOY AUTOMATIZADO CLYVO VET NO AZURE (ACR + ACI)"
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

echo ">> Obtendo credenciais de acesso ao ACR..."
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --query loginServer --output tsv)
ACR_PASSWORD=$(az acr credential show --name "$ACR_NAME" --query "passwords[0].value" --output tsv)

# ----------------------------------------------------------------------------
# 4. BUILD E PUSH DA IMAGEM DOCKER (NON-ROOT) PARA O ACR
# ----------------------------------------------------------------------------
echo ">> 3. Efetuando login no ACR via Azure CLI..."
az acr login --name "$ACR_NAME"

echo ">> 4. Construindo imagem Docker da aplicacao (Java 21 LTS Non-Root)..."
docker build -t "$IMAGE_NAME:$IMAGE_TAG" -f ../Dockerfile ..

echo ">> 5. Tageando e enviando a imagem para o ACR..."
docker tag "$IMAGE_NAME:$IMAGE_TAG" "$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"
docker push "$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"

# ----------------------------------------------------------------------------
# 5. DEPLOY DO BANCO DE DADOS EM CONTAINER NA AZURE (ACI)
# ----------------------------------------------------------------------------
echo ">> 6. Provisionando Banco de Dados PostgreSQL no Azure Container Instances..."
az container create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACI_DB_NAME" \
  --image postgres:16-alpine \
  --cpu 1 \
  --memory 1.5 \
  --ports 5432 \
  --dns-name-label "$DNS_NAME_DB" \
  --environment-variables \
      POSTGRES_DB="$DB_NAME" \
      POSTGRES_USER="$DB_USER" \
  --secure-environment-variables \
      POSTGRES_PASSWORD="$DB_PASS"

echo ">> Aguardando inicialização do banco de dados na nuvem..."
sleep 20
DB_FQDN=$(az container show --resource-group "$RESOURCE_GROUP" --name "$ACI_DB_NAME" --query "ipAddress.fqdn" --output tsv)
echo ">> Banco de dados ativo em: $DB_FQDN:5432"

# ----------------------------------------------------------------------------
# 6. DEPLOY DA APLICAÇÃO SPRING BOOT NO AZURE CONTAINER INSTANCES (ACI)
# ----------------------------------------------------------------------------
echo ">> 7. Provisionando Container da Aplicação no Azure Container Instances..."
az container create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACI_APP_NAME" \
  --image "$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG" \
  --registry-login-server "$ACR_LOGIN_SERVER" \
  --registry-username "$ACR_NAME" \
  --registry-password "$ACR_PASSWORD" \
  --cpu 1 \
  --memory 2.0 \
  --ports 8080 \
  --dns-name-label "$DNS_NAME_APP" \
  --environment-variables \
      SPRING_PROFILES_ACTIVE="prod" \
      DB_URL="jdbc:postgresql://$DB_FQDN:5432/$DB_NAME" \
      DB_USER="$DB_USER" \
      SERVER_PORT="8080" \
  --secure-environment-variables \
      DB_PASS="$DB_PASS" \
      JWT_SECRET="$JWT_SECRET"

# ----------------------------------------------------------------------------
# 7. EVIDÊNCIAS E TESTES DE ACESSO
# ----------------------------------------------------------------------------
APP_FQDN=$(az container show --resource-group "$RESOURCE_GROUP" --name "$ACI_APP_NAME" --query "ipAddress.fqdn" --output tsv)
APP_IP=$(az container show --resource-group "$RESOURCE_GROUP" --name "$ACI_APP_NAME" --query "ipAddress.ip" --output tsv)

echo "========================================================================"
echo ">> DEPLOY CONCLUÍDO COM SUCESSO!"
echo ">> URL da Aplicação Web: http://$APP_FQDN:8080/"
echo ">> URL do Swagger UI:   http://$APP_FQDN:8080/swagger-ui.html"
echo ">> IP Direto do App:    http://$APP_IP:8080/"
echo ">> FQDN do Banco:       $DB_FQDN:5432"
echo "========================================================================"
