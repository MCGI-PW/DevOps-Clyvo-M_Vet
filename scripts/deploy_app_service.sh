#!/usr/bin/env bash
# ============================================================================
# SCRIPT DE DEPLOY VIA AZURE CLI - OPÇÃO 2: APP SERVICE + BANCO PAAS
# Solução PaaS Nativa (Sem Containers)
# Cumpre os Requisitos 8.5, 8.6 e Critérios de Avaliação DevOps FIAP
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# 1. VARIÁVEIS DE CONFIGURAÇÃO DO AMBIENTE
# ----------------------------------------------------------------------------
RESOURCE_GROUP="rg-clyvovet-paas"
LOCATION="brazilsouth"
APP_SERVICE_PLAN="asp-clyvovet"
WEBAPP_NAME="clyvovet-app-${RANDOM}"
DB_SERVER_NAME="clyvovet-db-server-${RANDOM}"

DB_NAME="clyvovet"
DB_USER="clyvoadmin"
DB_PASS="ClyvoSecPass2026!"
JWT_SECRET="clyvo_secret_key_ultra_secure_minimum_32_chars_2026_devops"

echo "========================================================================"
echo ">> INICIANDO DEPLOY OPÇÃO 2: AZURE APP SERVICE + BANCO PAAS"
echo "========================================================================"

# 1. Criar Resource Group
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# 2. Criar Banco de Dados PaaS (Azure Database for PostgreSQL Flexible Server)
echo ">> Provisionando Banco de Dados PaaS PostgreSQL..."
az postgres flexible-server create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DB_SERVER_NAME" \
  --location "$LOCATION" \
  --admin-user "$DB_USER" \
  --admin-password "$DB_PASS" \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 16 \
  --yes

# Liberar acesso do firewall da Azure para o App Service
az postgres flexible-server firewall-rule create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DB_SERVER_NAME" \
  --rule-name AllowAllAzureIPs \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

DB_HOST="$DB_SERVER_NAME.postgres.database.azure.com"

# 3. Criar Plano do App Service (Linux)
echo ">> Criando App Service Plan..."
az appservice plan create \
  --name "$APP_SERVICE_PLAN" \
  --resource-group "$RESOURCE_GROUP" \
  --is-linux \
  --sku B1

# 4. Criar Web App (Java 21 LTS Nativo)
echo ">> Criando Azure Web App..."
az webapp create \
  --resource-group "$RESOURCE_GROUP" \
  --plan "$APP_SERVICE_PLAN" \
  --name "$WEBAPP_NAME" \
  --runtime "JAVA:21-java21"

# 5. Configurar Variáveis de Ambiente no App Service
echo ">> Configurando Application Settings..."
az webapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEBAPP_NAME" \
  --settings \
      SPRING_PROFILES_ACTIVE="prod" \
      DB_URL="jdbc:postgresql://$DB_HOST:5432/$DB_NAME?sslmode=require" \
      DB_USER="$DB_USER" \
      DB_PASS="$DB_PASS" \
      JWT_SECRET="$JWT_SECRET"

# 6. Compilar e Fazer Deploy do JAR
echo ">> Compilando pacote JAR com Maven..."
(cd ../.. && ./mvnw clean package -DskipTests)

echo ">> Efetuando deploy do JAR no Azure App Service..."
az webapp deploy \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEBAPP_NAME" \
  --src-path ../../target/*.jar \
  --type jar

echo ">> Deploy concluído! URL: https://$WEBAPP_NAME.azurewebsites.net/"
