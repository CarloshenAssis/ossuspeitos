# Servidor dedicado do Armed Mystery (fase 8): container Linux x86_64 que roda
# o servidor Godot headless autoritativo, pronto para o Railway.
#
# Estágios:
#   godot-tools  -> Godot 4.4.1 oficial (editor para exportar + template de
#                   release Linux), baixados do GitHub e verificados por SHA-512
#                   (imagem Python só no build; sem apt).
#   export       -> importa o projeto e exporta o preset "Linux Server"
#                   (dedicated_server=true: recursos visuais removidos).
#   export-test  -> (só CI) o mesmo export com os coordenadores de teste,
#                   para rodar a campanha de 8 clientes contra o container.
#   runtime-test -> (só CI) imagem de execução com o export de teste.
#   runtime      -> imagem final: binário de release + .pck + wrapper de
#                   start; usuário sem privilégios; nada é baixado ao iniciar.
#
# O Railway constrói o ÚLTIMO estágio (runtime). Build local:
#   docker build -t armed-mystery-server .
# Onde o Docker Hub limitar pulls, a mesma base (mesmo digest) pode vir de um
# espelho: --build-arg BASE_IMAGE=mirror.gcr.io/library/debian@sha256:... (idem
# TOOLS_IMAGE).

ARG BASE_IMAGE=debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251
ARG TOOLS_IMAGE=python:3.12-slim-bookworm@sha256:392307d22300de8b5986851a12d9176dfc0fc073e65bf6523ebd7dcbeb23564e

# --- Godot oficial, versão igual à dos workflows (4.4.1-stable) ---------------
# Estágio de build sem apt: Python da imagem (fixada por digest) baixa o
# release oficial, confere o SHA-512 publicado pelo Godot e extrai só o
# editor e o template de release Linux. Nada disso vai para a imagem final.
FROM ${TOOLS_IMAGE} AS godot-tools
ARG GODOT_VERSION=4.4.1-stable
ARG GODOT_EDITOR_SHA512=ef4e76880a514257175544952c61191106fdef3095b909bafed9fcbeb230c3e5533920a0f3012882dd4bbde83028a67549825794e2d2c3cf76eba7918b71370e
ARG GODOT_TEMPLATES_SHA512=8f461c7d6e91a0fbabfc95b1e4ca70ff1732c6f2920956a16b086ec2a85b5f7e238baf4dbce60dcc5630fae3bcb9a1fa2ae2027b92cb495c02d082705715e441
# Opcional: CA extra (PEM) de um proxy corporativo que re-termina TLS. Vazia no
# Railway e no CI.
ARG EXTRA_CA_PEM=""
COPY deploy/fetch_godot.py /tmp/fetch_godot.py
RUN GODOT_VERSION="${GODOT_VERSION}" GODOT_EDITOR_SHA512="${GODOT_EDITOR_SHA512}" \
    GODOT_TEMPLATES_SHA512="${GODOT_TEMPLATES_SHA512}" EXTRA_CA_PEM="${EXTRA_CA_PEM}" \
    python3 /tmp/fetch_godot.py /usr/local/bin/godot \
      "/root/.local/share/godot/export_templates/$(echo "${GODOT_VERSION}" | tr '-' '.')" \
 && rm /tmp/fetch_godot.py \
 && godot --headless --version

# --- Importação e export do servidor dedicado ---------------------------------
FROM godot-tools AS export
WORKDIR /src
COPY . .
# Importa os recursos (gera .godot/ dentro da imagem de build, nunca o cache
# do desenvolvedor) e exporta o preset dedicado. Falha de export = build falho.
RUN set -eu; \
    godot --headless --path /src --editor --quit > /tmp/import.log 2>&1 || { cat /tmp/import.log; exit 1; }; \
    if grep -E "SCRIPT ERROR|Parse Error" /tmp/import.log; then exit 1; fi; \
    mkdir -p /out; \
    godot --headless --path /src --export-release "Linux Server" /out/armed-mystery-server.x86_64 > /tmp/export.log 2>&1 || { cat /tmp/export.log; exit 1; }; \
    test -x /out/armed-mystery-server.x86_64; \
    test -s /out/armed-mystery-server.pck; \
    ls -la /out

# --- (CI) export com coordenadores de teste ------------------------------------
FROM export AS export-test
RUN set -eu; \
    mkdir -p /out-test; \
    godot --headless --path /src --export-release "Linux Server Test" /out-test/armed-mystery-server.x86_64 > /tmp/export-test.log 2>&1 || { cat /tmp/export-test.log; exit 1; }; \
    test -s /out-test/armed-mystery-server.pck

# --- Base de execução comum ---------------------------------------------------
FROM ${BASE_IMAGE} AS runtime-base
# Usuário sem privilégios com HOME gravável (user:// do Godot fica em
# ~/.local/share/godot/app_userdata). A pasta /app é somente leitura para ele.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --home-dir /home/app --create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY deploy/start-server.sh /app/start-server.sh
RUN chmod 0755 /app/start-server.sh
ENV HOME=/home/app \
    ARMED_MYSTERY_SERVER_BIN=/app/armed-mystery-server.x86_64 \
    ARMED_MYSTERY_SHUTDOWN_FILE=/tmp/armed-mystery.stop \
    ARMED_MYSTERY_SHUTDOWN_GRACE_SECONDS=8
# Porta padrão só quando PORT não vier do ambiente (o Railway injeta PORT).
EXPOSE 9080
STOPSIGNAL SIGTERM

# --- (CI) execução com o export de teste --------------------------------------
FROM runtime-base AS runtime-test
COPY --from=export-test /out-test/ /app/
USER app
ENTRYPOINT ["/app/armed-mystery-server.x86_64", "--headless"]

# --- Imagem final (produção) ---------------------------------------------------
FROM runtime-base AS runtime
ARG ARMED_MYSTERY_COMMIT=""
ENV ARMED_MYSTERY_COMMIT=${ARMED_MYSTERY_COMMIT}
COPY --from=export /out/ /app/
USER app
ENTRYPOINT ["/app/start-server.sh"]
