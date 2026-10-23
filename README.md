# ☁️ Clyvo Vet - Documentação Oficial de DevOps & Cloud Computing

> Projeto acadêmico para a disciplina de **DevOps Tools & Cloud Computing** (FIAP).  
> Solução de Gestão Veterinária desenvolvida com **Java 21 LTS**, **Spring Boot 3**, **Docker (Non-Root)**, **Azure Container Registry (ACR)**, **Azure Container Instances (ACI)** e **Banco de Dados em Nuvem**.

---

## 📌 Sumário
1. [Descrição da Solução](#1-descrição-da-solução)
2. [Benefícios para o Negócio](#2-benefícios-para-o-negócio)
3. [Desenho da Arquitetura Cloud (DevOps Tools)](#3-desenho-da-arquitetura-cloud-devops-tools)
4. [Banco de Dados na Nuvem e Tabelas CORE](#4-banco-de-dados-na-nuvem-e-tabelas-core)
5. [Guia de Deploy Passo a Passo via Azure CLI](#5-guia-de-deploy-passo-a-passo-via-azure-cli)
6. [Roteiro de Demonstração do CRUD no Banco de Dados (Vídeo)](#6-roteiro-de-demonstração-do-crud-no-banco-de-dados-vídeo)
7. [Checklist de Verificação contra Penalidades](#7-checklist-de-verificação-contra-penalidades)
8. [Dados da Entrega (Integrantes e Links)](#8-dados-da-entrega-integrantes-e-links)

---

## 1. Descrição da Solução
O **Clyvo Vet** é uma plataforma integrada de gestão hospitalar e clínica veterinária que conecta:
* **Tutores**: Realizam o cadastro de seus animais, agendam consultas médicas presenciais ou por telemedicina e gerenciam o histórico clínico.
* **Médicos Veterinários**: Controlam a fila de atendimentos, registram diagnósticos e lavram prontuários clínicos detalhados com prescrição médica.
* **Clínicas Veterinárias**: Credenciam corpo clínico, gerenciam autorizações de acesso a dados (LGPD) e organizam transferências de consultas.

A aplicação possui uma arquitetura híbrida com **Camada Web Server-Side (Thymeleaf)** para navegadores desktop e **API RESTful stateless** para integração com aplicativos mobile.

---

## 2. Benefícios para o Negócio
* **Redução de No-Shows e Conflitos de Agenda**: Validações em tempo real impedem choque de horários entre médicos veterinários e garantem agendamento apenas em horários futuros.
* **Segurança e Integridade Clínica (3NF)**: Separação estrita entre o evento de agendamento (`consulta`) e o ato médico (`prontuario`), garantindo rastreabilidade do prontuário para auditorias e responsabilidade técnica médica.
* **Conformidade com a LGPD**: O tutor tem governança total sobre o consentimento de acesso aos dados do seu pet, podendo revogar autorizações com cancelamento em cascata de consultas pendentes.
* **Escalabilidade e Disponibilidade na Nuvem**: Execução em containers Docker sobre a infraestrutura da Microsoft Azure, eliminando custos de servidores dedicados locais e permitindo escalabilidade sob demanda.

---

## 3. Desenho da Arquitetura Cloud (DevOps Tools)

A arquitetura adota a **Opção 1 (aplicação containerizada com ACR + ACI)**, conectada ao **Oracle Database da FIAP**:

```
                         [ DESENVOLVEDOR ]
                                │
                                ▼  az acr build (Dockerfile multi-stage)
            ┌───────────────────────────────────────────────────┐
            │          AZURE CONTAINER REGISTRY (ACR)           │
            │   Imagem: clyvovet-api:v2.0.0 (Java 21 Non-Root)  │
            └─────────────────────────┬─────────────────────────┘
                                      │ pull da imagem
                                      ▼
  [ CLIENTE EXTERNO ]     ┌────────────────────────────────────────┐
 (Navegador Web / Mobile)─►│   AZURE CONTAINER INSTANCES (ACI)     │
       HTTP:8080          │   App Spring Boot (Java 21 JRE)        │
                          │   Usuário Non-Root UID 10001           │
                          │   Perfis: prod,demo                    │
                          └───────────────────┬────────────────────┘
                                              │ JDBC thin :1521
                                              ▼
                          ┌────────────────────────────────────────┐
                          │   ORACLE DATABASE (oracle.fiap.com.br) │
                          │   Schema criado pelo Flyway (V1..V6)   │
                          └────────────────────────────────────────┘
```

### Explicação do Funcionamento:
1. **Segurança do Container (Requisito 8.2)**: A imagem roda com usuário não privilegiado (`appuser`, UID 10001), reduzindo o risco de escalada de privilégios.
2. **Registro de Imagens (ACR)**: Repositório privado na Azure. O build é feito na própria Azure (`az acr build`, `linux/amd64`) a partir do `Dockerfile` multi-stage, que clona a branch `main` da API.
3. **Execução Serverless (ACI)**: O Azure Container Instances executa o container da aplicação com IP público e FQDN dedicado.
4. **Banco de Dados**: A aplicação conecta-se ao Oracle da FIAP pela porta 1521. Ao subir, o **Flyway** cria ou atualiza o schema (migrations `V1..V6`) e o perfil `demo` carrega os dados de demonstração.
5. **Segredos**: `DB_URL`, `DB_USER`, `DB_PASS`, `JWT_SECRET` e `DEMO_PASSWORD` são lidos de variáveis de ambiente e enviados ao ACI como `--secure-environment-variables`. Nenhuma credencial fica no código.

---

## 4. Banco de Dados na Nuvem e Tabelas CORE

Conforme os **Requisitos 3.3 e 3.4**, a solução utiliza duas tabelas que representam o coração funcional da plataforma veterinária:

1. **`CONSULTA` (Tabela CORE 1)**: Registra o evento de agendamento, data/hora, modalidade (Presencial/Telemedicina), valor e status da consulta.
2. **`PRONTUARIO` (Tabela CORE 2)**: Registra o histórico clínico, observações médicas, hipótese diagnóstica e prescrições do médico veterinário, associada via chave estrangeira 1:1 à `CONSULTA`.

> 📄 **DDL Completo**: O script com toda a estrutura, PKs, FKs, constraints e comentários está salvo no arquivo obrigatório:  
> 👉 [`script_bd.sql`](./script_bd.sql)
>
> ℹ️ O `script_bd.sql` é o DDL comentado das tabelas CORE usado na demonstração do CRUD (seção 6). O schema completo da aplicação (contas, perfis, autorizações LGPD, notificações etc.) é criado automaticamente pelo **Flyway** a partir das migrations [`V1..V6`](https://github.com/MCGI-PW/API-Clyvo-M_Vet/tree/main/src/main/resources/db/migration) do repositório da API, com o DER em [`docs/DER.md`](https://github.com/MCGI-PW/API-Clyvo-M_Vet/blob/main/docs/DER.md).

---

## 5. Guia de Deploy Passo a Passo via Azure CLI

> **Atenção**: O comando `az` deve ser utilizado para criar 100% dos recursos, sem uso do Portal Web (Requisito 8.1).

### Passo 1: Autenticar na Azure
```bash
az login
```

### Passo 2: Executar o Script Automatizado
Disponibilizamos um script completo que cria o Resource Group, o ACR, realiza o build/push da imagem e inicia os containers no ACI:

```bash
cd scripts
chmod +x deploy_acr_aci.sh
./deploy_acr_aci.sh
```

> ⚠️ O `Dockerfile` clona a branch `main` do repositório da API. **Faça o push das alterações da API antes do deploy.**

As credenciais são obrigatórias e lidas do ambiente (o script para com erro se faltar alguma):

```bash
export DB_USER="rmXXXXXX"                      # usuário Oracle FIAP
export DB_PASS="********"                      # senha Oracle FIAP
export JWT_SECRET="$(openssl rand -base64 48)"
export DEMO_PASSWORD="********"                # senha das contas de demonstração
./deploy_acr_aci.sh
```

### Ou execute manualmente comando por comando:

```bash
# 1. Definir variáveis (credenciais já exportadas no passo anterior)
RG="rg-clyvovet-fiap"
LOC="brazilsouth"   # regiões permitidas na assinatura FIAP: brazilsouth, southcentralus, mexicocentral, chilecentral, southafricanorth
ACR="acrclyvovet$RANDOM"
DB_URL="jdbc:oracle:thin:@oracle.fiap.com.br:1521:ORCL"

# 2. Criar Resource Group
az group create --name $RG --location $LOC

# 3. Criar Azure Container Registry (ACR)
az acr create --resource-group $RG --name $ACR --sku Basic --admin-enabled true
ACR_LOGIN=$(az acr show --name $ACR --query loginServer -o tsv)
ACR_PWD=$(az acr credential show --name $ACR --query "passwords[0].value" -o tsv)

# 4. Build da imagem Non-Root diretamente no ACR (na raiz deste repositório)
az acr build --registry $ACR --image clyvovet-api:v2.0.0 --platform linux/amd64 --file Dockerfile .

# 5. Criar o container da aplicação no ACI
az container create \
  --resource-group $RG \
  --name aci-clyvovet-app \
  --image $ACR_LOGIN/clyvovet-api:v2.0.0 \
  --registry-login-server $ACR_LOGIN \
  --registry-username $ACR \
  --registry-password $ACR_PWD \
  --os-type Linux --cpu 1 --memory 2.0 --ports 8080 \
  --ip-address Public \
  --dns-name-label clyvovet-app-$RANDOM \
  --environment-variables SPRING_PROFILES_ACTIVE="prod,demo" SERVER_PORT="8080" \
  --secure-environment-variables \
      DB_URL="$DB_URL" DB_USER="$DB_USER" DB_PASS="$DB_PASS" \
      JWT_SECRET="$JWT_SECRET" DEMO_PASSWORD="$DEMO_PASSWORD"

# 6. Obter a URL pública
az container show --resource-group $RG --name aci-clyvovet-app --query "ipAddress.fqdn" -o tsv
# Aplicação: http://<fqdn>:8080/   ·   Swagger: http://<fqdn>:8080/swagger-ui.html
# Logs:      az container logs -g $RG -n aci-clyvovet-app
```

### Execução local com Docker Compose (Oracle Free em container)

```bash
export DB_PASS="uma-senha-local" JWT_SECRET="$(openssl rand -base64 48)" DEMO_PASSWORD="senha123"
docker compose up --build
# http://localhost:8080  (a primeira subida do Oracle leva alguns minutos)
```

---

## 6. Roteiro de Demonstração do CRUD no Banco de Dados (Vídeo)

Para a gravação do vídeo (Requisito 9.2 e 9.3), execute os comandos abaixo diretamente no cliente de banco de dados (SQL Developer, DBeaver ou DataGrip conectado ao Oracle da FIAP) para evidenciar **SELECT antes e depois de cada operação**:

### Operação 1: READ (Consulta Inicial)
Exibe os registros existentes relacionando as duas tabelas CORE (`CONSULTA` e `PRONTUARIO`):
```sql
SELECT 
    c.id_consulta,
    c.data_hora,
    c.status,
    c.valor,
    p.diagnostico,
    p.anotacoes_clinicas
FROM consulta c
LEFT JOIN prontuario p ON c.id_consulta = p.id_consulta;
```

### Operação 2: CREATE (Inclusão)
Insere uma nova consulta e exibe imediatamente via SELECT:
```sql
-- Inserir nova consulta
INSERT INTO consulta (id_consulta, id_pet, id_veterinario, data_hora, modalidade, status, motivo, valor)
VALUES ('A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3', '11111111111111111111111111111111', '01010101010101010101010101010101', CURRENT_TIMESTAMP + INTERVAL '2' DAY, 'PRESENCIAL', 'AGENDADO', 'Check-up geral de rotina', 170.00);

-- EVIDÊNCIA NO VÍDEO: Exibir o registro criado
SELECT * FROM consulta WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';
```

### Operação 3: UPDATE (Alteração)
Altera o status da consulta para CONCLUIDA e insere o respectivo prontuário clínico:
```sql
-- Atualizar status da consulta
UPDATE consulta 
SET status = 'CONCLUIDA', valor = 190.00 
WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';

-- Inserir prontuário médico vinculado à consulta (Tabela CORE 2)
INSERT INTO prontuario (id_prontuario, id_consulta, id_veterinario, anotacoes_clinicas, diagnostico, prescricao)
VALUES ('B3B3B3B3B3B3B3B3B3B3B3B3B3B3B3B3', 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3', '01010101010101010101010101010101', 'Animal clinicamente higido. Escore corporal ideal.', 'Exame de rotina satisfatorio.', 'Manter alimentacao premium e vacinacao em dia.');

-- EVIDÊNCIA NO VÍDEO: Exibir as duas tabelas atualizadas via JOIN
SELECT c.id_consulta, c.status, c.valor, pr.diagnostico, pr.anotacoes_clinicas 
FROM consulta c 
JOIN prontuario pr ON c.id_consulta = pr.id_consulta 
WHERE c.id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';
```

### Operação 4: DELETE (Exclusão)
Remove o prontuário e a consulta recém-criada, comprovando a deleção com SELECT vazio:
```sql
-- Remover prontuário e consulta
DELETE FROM prontuario WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';
DELETE FROM consulta WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';

-- EVIDÊNCIA NO VÍDEO: Comprovar que o registro não existe mais
SELECT * FROM consulta WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';
```

---

## 7. Checklist de Verificação contra Penalidades

| Exigência / Risco de Penalidade | Status | Como foi atendido |
| :--- | :---: | :--- |
| **Entrega em LOCALHOST (-100 pts / Zero)** | 🛡️ Protegido | Provisionamento em nuvem pública Azure (ACR + ACI). |
| **Sem descrição da solução (-10 pts)** | 🛡️ Protegido | Seção 1 deste README. |
| **Sem benefício para o negócio (-10 pts)** | 🛡️ Protegido | Seção 2 deste README. |
| **Sem orientações de deploy/teste (-30 pts)** | 🛡️ Protegido | Seções 5 e 6 deste README. |
| **Sem evidência do CRUD no banco (-30 pts)** | 🛡️ Protegido | Queries detalhadas com SELECTs antes e depois no script e README. |
| **Sem DDL das tabelas com comentários (-10 pts)** | 🛡️ Protegido | Arquivo [`script_bd.sql`](./script_bd.sql) com PKs, FKs e COMMENTs. |
| **Não manipular pelo menos 2 linhas significativas (-20 pts)** | 🛡️ Protegido | Carga inicial com Thor e Mia contendo consultas e prontuários reais. |
| **Utilizar apenas 1 tabela no CRUD (-20 pts)** | 🛡️ Protegido | CRUD manipulando `CONSULTA` e `PRONTUARIO` conjuntamente. |
| **Tabelas que não são do CORE (-30 pts)** | 🛡️ Protegido | Uso direto do coração da aplicação veterinária. |
| **Misturar opções de entrega (-40 pts)** | 🛡️ Protegido | Solução 100% containerizada com ACR + ACI (o script da opção App Service foi removido). |
| **Dados sensíveis expostos no código (-20 pts)** | 🛡️ Protegido | Credenciais e segredos injetados exclusivamente por variáveis de ambiente. |
| **Container rodando como root/admin (-10 pts)** | 🛡️ Protegido | `Dockerfile` com usuário `appuser` (UID 10001). |
| **Recursos não criados via Azure CLI (-30 pts)** | 🛡️ Protegido | Scripts 100% baseados em comandos `az`. |

---

## 8. Dados da Entrega (Integrantes e Links)

### 👥 Integrantes do Grupo:
* **Maicon Douglas** - RM561279
* **Gabriel (Gabs)** - RM561551
* **Charlles** - RM566482
* **Iago D.** - RM565708

### 🔗 Links Oficiais:
* **Repositório GitHub (DevOps)**: [https://github.com/MCGI-PW/DevOps-Clyvo-M_Vet](https://github.com/MCGI-PW/DevOps-Clyvo-M_Vet)
* **Repositório GitHub (API Java)**: [https://github.com/MCGI-PW/API-Clyvo-M_Vet](https://github.com/MCGI-PW/API-Clyvo-M_Vet)
* **Link do Vídeo no YouTube**: [https://youtu.be/548lg3zc7Mw](https://youtu.be/548lg3zc7Mw)
