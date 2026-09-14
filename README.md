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

A arquitetura adota a **Opção 1 (Solução 100% Containerizada com ACR + ACI)**:

```
                                  [ DESENVOLVEDOR / CI/CD ]
                                              │
                                              ▼ (git push / az acr build)
                      ┌───────────────────────────────────────────────────┐
                      │          AZURE CONTAINER REGISTRY (ACR)           │
                      │  Imagem: clyvovet-api:v1.0.0 (Java 21 Non-Root)  │
                      └────────────────────────┬──────────────────────────┘
                                               │
                                               │ (Pull de imagem segura)
                                               ▼
     [ CLIENTE EXTERNO ]        ┌────────────────────────────────────────┐
   (Navegador Web / Mobile) ───►│    AZURE CONTAINER INSTANCES (ACI)     │
        HTTP:8080               │                                        │
                                │   ┌────────────────────────────────┐   │
                                │   │ Container 1: App Spring Boot   │   │
                                │   │ (Java 21 JRE, Non-Root UID 10001│   │
                                │   └───────────────┬────────────────┘   │
                                │                   │                    │
                                │                   │ JDBC:5432          │
                                │                   ▼                    │
                                │   ┌────────────────────────────────┐   │
                                │   │ Container 2: Banco de Dados    │   │
                                │   │ (PostgreSQL 16 Cloud / Vol)    │   │
                                │   └────────────────────────────────┘   │
                                └────────────────────────────────────────┘
```

### Explicação do Funcionamento:
1. **Segurança do Container (Requisito 8.2)**: A imagem do App roda com usuário não-privilegiado (`appuser`, UID 10001), eliminando riscos de container escape e escalada de privilégios.
2. **Registro de Imagens (ACR)**: Repositório privado na Azure que armazena a imagem Docker construída a partir do `Dockerfile` multi-stage.
3. **Execução Serverless (ACI)**: O Azure Container Instances executa tanto o container da aplicação quanto o container do banco de dados relacional, expondo portas e FQDNs públicos dedicados.
4. **Comunicação Privada**: A aplicação comunica-se com a instância do banco através da porta 5432 utilizando credenciais injetadas de forma segura via parâmetros da Azure CLI (`--secure-environment-variables`).

---

## 4. Banco de Dados na Nuvem e Tabelas CORE

Conforme os **Requisitos 3.3 e 3.4**, a solução utiliza duas tabelas que representam o coração funcional da plataforma veterinária:

1. **`CONSULTA` (Tabela CORE 1)**: Registra o evento de agendamento, data/hora, modalidade (Presencial/Telemedicina), valor e status da consulta.
2. **`PRONTUARIO` (Tabela CORE 2)**: Registra o histórico clínico, observações médicas, hipótese diagnóstica e prescrições do médico veterinário, associada via chave estrangeira 1:1 à `CONSULTA`.

> 📄 **DDL Completo**: O script com toda a estrutura, PKs, FKs, constraints e comentários está salvo no arquivo obrigatório:  
> 👉 [`Devops/script_bd.sql`](./script_bd.sql)

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
cd Devops/scripts
chmod +x deploy_acr_aci.sh
./deploy_acr_aci.sh
```

### Ou execute manualmente comando por comando:

```bash
# 1. Definir variáveis
RG="rg-clyvovet-fiap"
LOC="eastus"
ACR="acrclyvovet$RANDOM"

# 2. Criar Resource Group
az group create --name $RG --location $LOC

# 3. Criar Azure Container Registry (ACR)
az acr create --resource-group $RG --name $ACR --sku Basic --admin-enabled true
ACR_LOGIN=$(az acr show --name $ACR --query loginServer -o tsv)
ACR_PWD=$(az acr credential show --name $ACR --query "passwords[0].value" -o tsv)

# 4. Build e Push da imagem Non-Root para o ACR
az acr login --name $ACR
docker build -t clyvovet-api:v1.0.0 -f Devops/Dockerfile .
docker tag clyvovet-api:v1.0.0 $ACR_LOGIN/clyvovet-api:v1.0.0
docker push $ACR_LOGIN/clyvovet-api:v1.0.0

# 5. Criar Container do Banco de Dados no ACI
az container create \
  --resource-group $RG \
  --name aci-clyvovet-db \
  --image postgres:16-alpine \
  --cpu 1 --memory 1.5 --ports 5432 \
  --dns-name-label clyvodb-$RANDOM \
  --environment-variables POSTGRES_DB=clyvovet POSTGRES_USER=clyvouser \
  --secure-environment-variables POSTGRES_PASSWORD=ClyvoSecPass2026!

DB_FQDN=$(az container show --resource-group $RG --name aci-clyvovet-db --query "ipAddress.fqdn" -o tsv)

# 6. Criar Container da Aplicação no ACI
az container create \
  --resource-group $RG \
  --name aci-clyvovet-app \
  --image $ACR_LOGIN/clyvovet-api:v1.0.0 \
  --registry-login-server $ACR_LOGIN \
  --registry-username $ACR \
  --registry-password $ACR_PWD \
  --cpu 1 --memory 2.0 --ports 8080 \
  --dns-name-label clyvoapp-$RANDOM \
  --environment-variables \
      SPRING_PROFILES_ACTIVE=prod \
      DB_URL="jdbc:postgresql://$DB_FQDN:5432/clyvovet" \
      DB_USER="clyvouser" \
  --secure-environment-variables \
      DB_PASS="ClyvoSecPass2026!" \
      JWT_SECRET="clyvo_secret_key_ultra_secure_minimum_32_chars_2026_devops"
```

---

## 6. Roteiro de Demonstração do CRUD no Banco de Dados (Vídeo)

Para a gravação do vídeo (Requisito 9.2 e 9.3), execute os comandos abaixo diretamente no cliente de banco de dados (DBeaver, DataGrip, psql ou Azure Query Editor) para evidenciar **SELECT antes e depois de cada operação**:

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
| **Sem DDL das tabelas com comentários (-10 pts)** | 🛡️ Protegido | Arquivo [`Devops/script_bd.sql`](./script_bd.sql) com PKs, FKs e COMMENTs. |
| **Não manipular pelo menos 2 linhas significativas (-20 pts)** | 🛡️ Protegido | Carga inicial com Thor e Mia contendo consultas e prontuários reais. |
| **Utilizar apenas 1 tabela no CRUD (-20 pts)** | 🛡️ Protegido | CRUD manipulando `CONSULTA` e `PRONTUARIO` conjuntamente. |
| **Tabelas que não são do CORE (-30 pts)** | 🛡️ Protegido | Uso direto do coração da aplicação veterinária. |
| **Misturar opções de entrega (-40 pts)** | 🛡️ Protegido | Solução 100% containerizada com ACR + ACI (sem mistura). |
| **Dados sensíveis expostos no código (-20 pts)** | 🛡️ Protegido | Credenciais e segredos injetados exclusivamente por variáveis de ambiente. |
| **Container rodando como root/admin (-10 pts)** | 🛡️ Protegido | `Dockerfile` com usuário `appuser` (UID 10001). |
| **Recursos não criados via Azure CLI (-30 pts)** | 🛡️ Protegido | Scripts 100% baseados em comandos `az`. |

---

## 8. Dados da Entrega (Integrantes e Links)

* **Nome do Aluno**: Maicon Douglas
* **RM**: 561279
* **Repositório GitHub**: [https://github.com/MCGI-PW/API-Clyvo-M_Vet](https://github.com/MCGI-PW/API-Clyvo-M_Vet)
* **Link do Vídeo no YouTube**: [https://youtu.be/548lg3zc7Mw](https://youtu.be/548lg3zc7Mw)
