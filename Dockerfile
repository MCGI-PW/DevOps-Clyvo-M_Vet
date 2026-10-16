# ============================================================================
# DOCKERFILE - CLYVO VETERINARY API (JAVA 21 LTS STANDALONE)
# Requisito 8.2: Execução estritamente NON-ROOT (sem privilégios administrativos)
# Padrão: Multi-stage Build otimizado para produção e CI/CD
# ============================================================================

# ----------------------------------------------------------------------------
# ESTÁGIO 1: Obtenção do Código e Build da Aplicação com Java 21 LTS
# ----------------------------------------------------------------------------
FROM eclipse-temurin:21-jdk-jammy AS builder

WORKDIR /build

# Instala Git para clonagem do repositório oficial da aplicação Java
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Clona o repositório público oficial da aplicação Java
ARG GIT_REF=main
RUN git clone --depth 1 --branch ${GIT_REF} https://github.com/MCGI-PW/API-Clyvo-M_Vet.git .

# Concede permissão de execução ao wrapper e compila o pacote JAR
RUN chmod +x mvnw && ./mvnw clean package -DskipTests -B

# ----------------------------------------------------------------------------
# ESTÁGIO 2: Imagem Final de Execução (Runtime Minimalista e Seguro)
# ----------------------------------------------------------------------------
FROM eclipse-temurin:21-jre-jammy AS runner

WORKDIR /app

# [SEGURANÇA - REQUISITO 8.2] Criação de usuário e grupo não-privilegiados (NON-ROOT)
# UID/GID 10001 garante isolamento contra escalada de privilégios no host
RUN addgroup --system --gid 10001 appgroup && \
    adduser --system --uid 10001 --ingroup appgroup --no-create-home appuser

# Copia o JAR compilado a partir do estágio de build
COPY --from=builder /build/target/*.jar app.jar

# Define a propriedade do arquivo para o usuário não-root
RUN chown -R appuser:appgroup /app

# Alterna para o usuário não-root (Obrigatório para conformidade de segurança Azure ACI)
USER 10001:10001

# Porta exposta pela aplicação
EXPOSE 8080

# Variáveis de ambiente padrão para a JVM
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"

# Comando de inicialização seguro
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
