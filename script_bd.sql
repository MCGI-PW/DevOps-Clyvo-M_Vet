-- ============================================================================
-- SCRIPT DE BANCO DE DADOS - CLYVO VET (SPRINT DEVOPS & CLOUD COMPUTING)
-- Arquivo Obrigatório: script_bd.sql
-- Descrição: DDL estruturado com tabelas CORE, PKs, FKs, constraints e comentários.
-- Compatível com: Oracle Database (FIAP), PostgreSQL e Azure SQL.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABELA: VETERINARIO (Entidade de Suporte para o Core)
-- ----------------------------------------------------------------------------
CREATE TABLE veterinario (
    id_veterinario RAW(16) DEFAULT SYS_GUID() NOT NULL,
    nome VARCHAR2(100) NOT NULL,
    crmv VARCHAR2(20) NOT NULL,
    especialidade VARCHAR2(100),
    telefone VARCHAR2(20),
    email VARCHAR2(100),
    ativo NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_veterinario PRIMARY KEY (id_veterinario),
    CONSTRAINT uk_veterinario_crmv UNIQUE (crmv)
);

COMMENT ON TABLE veterinario IS 'Armazena os medicos veterinarios credenciados para atendimento clinico.';
COMMENT ON COLUMN veterinario.id_veterinario IS 'Chave primaria do veterinario (UUID armazenado em RAW(16)).';
COMMENT ON COLUMN veterinario.nome IS 'Nome completo do medico veterinario.';
COMMENT ON COLUMN veterinario.crmv IS 'Registro profissional no Conselho Regional de Medicina Veterinaria.';
COMMENT ON COLUMN veterinario.ativo IS 'Flag booleana (1=Ativo, 0=Inativo).';

-- ----------------------------------------------------------------------------
-- 2. TABELA: PET (Entidade de Suporte para o Core)
-- ----------------------------------------------------------------------------
CREATE TABLE pet (
    id_pet RAW(16) DEFAULT SYS_GUID() NOT NULL,
    nome VARCHAR2(50) NOT NULL,
    especie VARCHAR2(30) NOT NULL,
    raca VARCHAR2(50),
    sexo VARCHAR2(10),
    data_nascimento DATE,
    peso NUMBER(5,2),
    ativo NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_pet PRIMARY KEY (id_pet)
);

COMMENT ON TABLE pet IS 'Armazena os pacientes animais atendidos pela plataforma.';
COMMENT ON COLUMN pet.id_pet IS 'Chave primaria do pet (UUID em formato binario RAW(16)).';
COMMENT ON COLUMN pet.nome IS 'Nome do animal de estimacao.';
COMMENT ON COLUMN pet.especie IS 'Especie do animal (ex: Canina, Felina).';
COMMENT ON COLUMN pet.ativo IS 'Status do cadastro do pet (1=Ativo, 0=Inativo).';

-- ----------------------------------------------------------------------------
-- 3. TABELA CORE 1: CONSULTA (Evento de Atendimento e Agendamento Clinico)
-- ----------------------------------------------------------------------------
CREATE TABLE consulta (
    id_consulta RAW(16) DEFAULT SYS_GUID() NOT NULL,
    id_pet RAW(16) NOT NULL,
    id_veterinario RAW(16) NOT NULL,
    data_hora TIMESTAMP NOT NULL,
    modalidade VARCHAR2(20) DEFAULT 'PRESENCIAL' NOT NULL,
    status VARCHAR2(20) DEFAULT 'AGENDADO' NOT NULL,
    motivo VARCHAR2(255),
    valor NUMBER(10,2) DEFAULT 0.00 NOT NULL,
    data_criacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pk_consulta PRIMARY KEY (id_consulta),
    CONSTRAINT fk_consulta_pet FOREIGN KEY (id_pet) REFERENCES pet(id_pet) ON DELETE CASCADE,
    CONSTRAINT fk_consulta_veterinario FOREIGN KEY (id_veterinario) REFERENCES veterinario(id_veterinario),
    CONSTRAINT chk_consulta_modalidade CHECK (modalidade IN ('PRESENCIAL', 'TELEMEDICINA')),
    CONSTRAINT chk_consulta_status CHECK (status IN ('AGENDADO', 'EM_ANDAMENTO', 'CONCLUIDA', 'CANCELADA'))
);

COMMENT ON TABLE consulta IS 'Tabela CORE 1: Registra o evento do atendimento veterinario, data/hora, modalidade e status.';
COMMENT ON COLUMN consulta.id_consulta IS 'Chave primaria da consulta (UUID em RAW(16)).';
COMMENT ON COLUMN consulta.id_pet IS 'Chave estrangeira referenciando o pet paciente.';
COMMENT ON COLUMN consulta.id_veterinario IS 'Chave estrangeira referenciando o medico veterinario responsavel.';
COMMENT ON COLUMN consulta.data_hora IS 'Data e hora programada para a realizacao do atendimento.';
COMMENT ON COLUMN consulta.modalidade IS 'Tipo de consulta (PRESENCIAL ou TELEMEDICINA).';
COMMENT ON COLUMN consulta.status IS 'Status da consulta (AGENDADO, EM_ANDAMENTO, CONCLUIDA, CANCELADA).';
COMMENT ON COLUMN consulta.valor IS 'Valor cobrado pelo atendimento medico.';

-- ----------------------------------------------------------------------------
-- 4. TABELA CORE 2: PRONTUARIO (Ato Medico e Historico Clinico Normalizado 3NF)
-- ----------------------------------------------------------------------------
CREATE TABLE prontuario (
    id_prontuario RAW(16) DEFAULT SYS_GUID() NOT NULL,
    id_consulta RAW(16) NOT NULL,
    id_veterinario RAW(16) NOT NULL,
    anotacoes_clinicas VARCHAR2(4000) NOT NULL,
    diagnostico VARCHAR2(500),
    prescricao VARCHAR2(1000),
    data_registro TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pk_prontuario PRIMARY KEY (id_prontuario),
    CONSTRAINT uk_prontuario_consulta UNIQUE (id_consulta),
    CONSTRAINT fk_prontuario_consulta FOREIGN KEY (id_consulta) REFERENCES consulta(id_consulta) ON DELETE CASCADE,
    CONSTRAINT fk_prontuario_veterinario FOREIGN KEY (id_veterinario) REFERENCES veterinario(id_veterinario)
);

COMMENT ON TABLE prontuario IS 'Tabela CORE 2: Registra o prontuario clinico do animal, observacoes medicas e prescricoes (3NF).';
COMMENT ON COLUMN prontuario.id_prontuario IS 'Chave primaria do prontuario (UUID em RAW(16)).';
COMMENT ON COLUMN prontuario.id_consulta IS 'Chave estrangeira relacionando 1:1 com a consulta realizada.';
COMMENT ON COLUMN prontuario.id_veterinario IS 'Chave estrangeira do veterinario que lavrou o prontuario.';
COMMENT ON COLUMN prontuario.anotacoes_clinicas IS 'Relato detalhado do estado de saude do animal e exames fisicos.';
COMMENT ON COLUMN prontuario.diagnostico IS 'Conclusao clinica ou hipotese diagnostica.';
COMMENT ON COLUMN prontuario.prescricao IS 'Medicamentos receitados, posologia e recomendacoes.';
COMMENT ON COLUMN prontuario.data_registro IS 'Carimbo de data e hora do registro medico.';

-- ============================================================================
-- 5. CARGA INICIAL DE DADOS (POPULAÇÃO SIGNIFICATIVA - REQUISITO 5)
-- ============================================================================

-- Insercao de Medicos Veterinarios
INSERT INTO veterinario (id_veterinario, nome, crmv, especialidade, telefone, email, ativo)
VALUES ('01010101010101010101010101010101', 'Dr. Carlos Mendes', 'CRMV-SP 12345', 'Clinica Geral e Cirurgia', '(11) 98888-1111', 'dr.carlos@veterinaria.com', 1);

INSERT INTO veterinario (id_veterinario, nome, crmv, especialidade, telefone, email, ativo)
VALUES ('02020202020202020202020202020202', 'Dra. Camila Nogueira', 'CRMV-SP 54321', 'Dermatologia e Nutrologia', '(11) 98888-2222', 'dra.camila@veterinaria.com', 1);

-- Insercao de Pets Pacientes
INSERT INTO pet (id_pet, nome, especie, raca, sexo, data_nascimento, peso, ativo)
VALUES ('11111111111111111111111111111111', 'Thor', 'Canina', 'Labrador Retriever', 'Macho', TO_DATE('2022-05-10', 'YYYY-MM-DD'), 32.50, 1);

INSERT INTO pet (id_pet, nome, especie, raca, sexo, data_nascimento, peso, ativo)
VALUES ('22222222222222222222222222222222', 'Mia', 'Felina', 'Siames', 'Femea', TO_DATE('2023-08-20', 'YYYY-MM-DD'), 4.20, 1);

-- Insercao de Registro 1 (Consulta e Prontuario Relacionados)
INSERT INTO consulta (id_consulta, id_pet, id_veterinario, data_hora, modalidade, status, motivo, valor)
VALUES ('A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1', '11111111111111111111111111111111', '01010101010101010101010101010101', TO_TIMESTAMP('2026-10-15 14:30:00', 'YYYY-MM-DD HH24:MI:SS'), 'PRESENCIAL', 'CONCLUIDA', 'Consulta de rotina e vacinacao anual', 180.00);

INSERT INTO prontuario (id_prontuario, id_consulta, id_veterinario, anotacoes_clinicas, diagnostico, prescricao)
VALUES ('B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1B1', 'A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1A1', '01010101010101010101010101010101', 'Animal ativo, mucosas normocoradas, hidratado, coracao e pulmoes sem alteracoes. Vacinacao V10 e antirrabica aplicadas com sucesso.', 'Paciente em excelente estado nutricional e higienico.', 'Vermifugacao preventiva a cada 4 meses. Retorno em 1 ano.');

-- Insercao de Registro 2 (Consulta e Prontuario Relacionados)
INSERT INTO consulta (id_consulta, id_pet, id_veterinario, data_hora, modalidade, status, motivo, valor)
VALUES ('A2A2A2A2A2A2A2A2A2A2A2A2A2A2A2A2', '22222222222222222222222222222222', '02020202020202020202020202020202', TO_TIMESTAMP('2026-10-16 10:00:00', 'YYYY-MM-DD HH24:MI:SS'), 'PRESENCIAL', 'CONCLUIDA', 'Prurido intenso na regiao auricular', 210.00);

INSERT INTO prontuario (id_prontuario, id_consulta, id_veterinario, anotacoes_clinicas, diagnostico, prescricao)
VALUES ('B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2B2', 'A2A2A2A2A2A2A2A2A2A2A2A2A2A2A2A2', '02020202020202020202020202020202', 'Presenca de cerumen marrom escuro em ambos os condutos auditivos externos. Escoriacoes por autotrauma na orelha direita.', 'Otite ceruminosa bilateral por hipersensibilidade alimentar.', 'Limpeza diaria com solucao ceruminolitica e gotas otologicas 2x ao dia por 10 dias. Retorno em 15 dias.');

COMMIT;

-- ============================================================================
-- 6. SCRIPTS DE DEMONSTRAÇÃO DO CRUD COMPLETO (REQUISITO 4, 5 e 9.3)
-- Execute individualmente na demonstracao em video exibindo o SELECT antes e depois!
-- ============================================================================

-- [READ / CONSULTA]
-- Consulta detalhada trazendo as duas tabelas CORE relacionadas (CONSULTA + PRONTUARIO)
SELECT 
    c.id_consulta,
    p.nome AS pet_nome,
    v.nome AS veterinario_nome,
    c.data_hora,
    c.status AS status_consulta,
    c.valor,
    pr.diagnostico,
    pr.anotacoes_clinicas,
    pr.data_registro
FROM consulta c
INNER JOIN pet p ON c.id_pet = p.id_pet
INNER JOIN veterinario v ON c.id_veterinario = v.id_veterinario
LEFT JOIN prontuario pr ON c.id_consulta = pr.id_consulta
ORDER BY c.data_hora DESC;

-- [CREATE / INCLUSÃO]
-- Inserindo um novo registro na tabela CORE 1 (Consulta) e na tabela CORE 2 (Prontuario)
INSERT INTO consulta (id_consulta, id_pet, id_veterinario, data_hora, modalidade, status, motivo, valor)
VALUES ('A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3', '11111111111111111111111111111111', '01010101010101010101010101010101', TO_TIMESTAMP('2026-11-20 16:00:00', 'YYYY-MM-DD HH24:MI:SS'), 'PRESENCIAL', 'AGENDADO', 'Check-up semestral preventivo', 150.00);

-- Exibir apos insercao da consulta:
SELECT * FROM consulta WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';

-- [UPDATE / ALTERAÇÃO]
-- Atualizando dados da Consulta e registrando Prontuario
UPDATE consulta 
SET status = 'CONCLUIDA', valor = 160.00 
WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';

INSERT INTO prontuario (id_prontuario, id_consulta, id_veterinario, anotacoes_clinicas, diagnostico, prescricao)
VALUES ('B3B3B3B3B3B3B3B3B3B3B3B3B3B3B3B3', 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3', '01010101010101010101010101010101', 'Animal em otimas condicoes de saude. Peso estavel.', 'Sem patologias diagnosticadas.', 'Manter dieta e exercicios.');

-- Exibir apos update e criacao do prontuario:
SELECT c.id_consulta, c.status, pr.diagnostico, pr.anotacoes_clinicas 
FROM consulta c 
JOIN prontuario pr ON c.id_consulta = pr.id_consulta 
WHERE c.id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';

-- [DELETE / EXCLUSÃO]
-- Exclusao do registro recem-criado (CASCADE remove prontuario automaticamente)
DELETE FROM prontuario WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';
DELETE FROM consulta WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';

-- Exibir apos delete comprovando a remocao:
SELECT * FROM consulta WHERE id_consulta = 'A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3A3';
