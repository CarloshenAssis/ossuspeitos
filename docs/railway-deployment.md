# Servidor dedicado no Railway (fase 8)

Estado em 24/09/2026:

- Serviço ativo em `wss://ossuspeitos-production.up.railway.app`, com porta
  interna 8080, segundo o operador.
- Um cliente Godot real, rodando no GitHub Actions, conectou pelo domínio
  público: TLS, WebSocket, protocolo 10 (antes das salas), entrada na sala,
  snapshots e estado da rodada.
- Fase 9: o mesmo processo passa a manter várias salas privadas (código de
  6 caracteres, PRONTO, até 8 por sala), com protocolo 11. Como o Railway
  republica a `main`, o merge da fase 9 troca o servidor online para o
  protocolo 11.
- **Ainda falta** uma partida completa com jogadores humanos pela internet
  (passo 6 abaixo) antes de anunciar o jogo como online.

## Arquitetura

- Um serviço Railway, uma réplica e uma região.
- Um processo Godot headless autoritativo, com uma sala de até 8
  participantes e o estado da partida em memória.
- Cliente → `wss://DOMINIO` → proxy público do Railway (termina TLS) →
  WebSocket sem TLS no `PORT` interno → `WebSocketMultiplayerPeer` do Godot.
- Sem banco, Redis, volume, matchmaking, contas ou segundo serviço.
- Reinício ou redeploy perde a partida em curso. Os jogadores recebem o aviso
  de encerramento e voltam ao menu.

## Como a imagem é feita (`Dockerfile` na raiz)

Estágios (o Railway constrói o último, `runtime`):

1. **`godot-tools`**:
   - baixa do GitHub o Godot 4.4.1-stable oficial (editor Linux x86_64 e
     pacote de templates);
   - confere o SHA-512 publicado pelo Godot, fixado no Dockerfile;
   - extrai só o editor e o template `linux_release.x86_64`;
   - usa a imagem `python:3.12-slim-bookworm`, fixada por digest, sem `apt`.
2. **`export`**:
   - importa o projeto (gera `.godot/` na imagem de build);
   - exporta o preset **"Linux Server"**: `dedicated_server=true`, recursos
     visuais removidos, `tests/` e `docs/` excluídos.
3. **`runtime`**:
   - base `debian:bookworm-slim`, fixada por digest;
   - contém só o binário de release (70 MB), o `.pck` (cerca de 0,5 MB) e o
     `start-server.sh`;
   - usuário `app` (uid 10001); `/app` é somente leitura e o HOME é
     gravável;
   - nada é baixado ao iniciar.

Por que export dedicado e não o projeto importado:

- **Template de release:** `OS.is_debug_build()` é falso, então os ganchos de
  teste restritos a debug ficam desligados pelo próprio engine: versão de
  protocolo simulada, atraso de rede e prazos curtos.
- **Tamanho:** a imagem final é pequena.

O mapa e as colisões vêm de código (`shared/mansion_map.gd`), não de GLB.
Por isso remover os visuais é seguro, e a campanha de 8 clientes passou
contra essa exportação.

## Comando de produção

`ENTRYPOINT ["/app/start-server.sh"]`. No Railway, **deixe o Start Command
vazio**: um Start Command no painel substitui o `ENTRYPOINT`.

O wrapper executa:

```
/app/armed-mystery-server.x86_64 --headless -- --mode=dedicated --shutdown-file=/tmp/armed-mystery.stop
```

- `--mode=dedicated`:
  - não abre menu nem cliente local e não cria câmera, HUD, áudio ou mesh;
  - carrega mundo e autoridades e continua disponível com a sala vazia.
- **Lista fechada de argumentos:** `mode`, `port`, `bind` e
  `shutdown-file`. Qualquer flag de teste (`--combat-test`, `--round-seed`,
  `--hosted`, `--stop-after-*`, `--test-*`…) faz o processo sair com
  código 2.
- **Sinal:** o Godot 4.4.1 não trata SIGTERM (medido: sai na hora com 143,
  sem avisar ninguém). O wrapper fica como PID 1, captura SIGTERM e SIGINT e
  cria o arquivo de parada. O servidor o verifica a cada cerca de 0,25 s e:
  - para de aceitar entradas;
  - avisa os jogadores (`shutdown_prepare`);
  - fecha os peers;
  - sai com 0.

  Se o jogo não sair em `ARMED_MYSTERY_SHUTDOWN_GRACE_SECONDS` (8 s), o
  wrapper manda SIGKILL. Não há loop de restart nem sleep infinito.
- Códigos de saída:
  - `0`: encerramento pedido;
  - `1`: falha em execução, por exemplo porta ocupada;
  - `2`: configuração inválida;
  - `137`: morto pelo prazo.

## Porta e endereço

| Fonte (ordem) | Uso |
| --- | --- |
| `--port=N` | execução manual; o start de produção não passa |
| `PORT` (ambiente) | o Railway injeta; é a fonte normal |
| `9080` | só quando nenhuma das duas existe (`port_source=default` no log) |

- **PORT inválida:** vazia, não inteira ou fora de 1–65535 gera erro claro e
  saída 2.
- **Porta ocupada:** saída 1 (`DEDICATED_FATAL reason=listen_failed`), sem
  trocar de porta.
- **Endereço de escuta:** `0.0.0.0`, que pode ser trocado por
  `ARMED_MYSTERY_BIND`. O servidor do menu local continua em `127.0.0.1`, ou
  na LAN se o jogador marcar.

## Configuração no painel do Railway

| Item | Valor |
| --- | --- |
| Repositório / branch | `CarloshenAssis/ossuspeitos` / `main` |
| Root Directory | vazio (raiz do repositório) |
| Builder | Dockerfile (definido em `railway.json`) |
| Dockerfile | `Dockerfile` (raiz) |
| Build Command | vazio |
| Start Command | **vazio** (usa o `ENTRYPOINT`) |
| Variável `PORT` | `8080` (fixa: deixa porta, domínio e healthcheck coerentes) |
| Variáveis opcionais | `ARMED_MYSTERY_STATUS_SECONDS` (padrão 60; 0 desliga), `ARMED_MYSTERY_SHUTDOWN_GRACE_SECONDS` (padrão 8), `ARMED_MYSTERY_MAX_ROOMS` (1 a 64, padrão 12) |
| Domínio público | gerar domínio `*.up.railway.app`, **target port 8080** |
| TCP Proxy | não usar (o cliente usa `wss://` pelo domínio HTTP) |
| Healthcheck Path | **vazio** (ver abaixo) |
| Restart policy | On Failure, máximo 10 (definido em `railway.json`) |
| Draining seconds | 15 (definido em `railway.json`; padrão do Railway é 0 = SIGKILL imediato) |
| Overlap seconds | 0 (padrão) |
| Réplicas | **1**, sem autoscaling horizontal |
| Serverless / App Sleeping | **desligado** |
| Volume | nenhum |
| Região | a mais próxima dos jogadores; para o Brasil, `US East Metal` (Virginia, `us-east4-eqdc4a`) tende a ter a menor latência entre as regiões atuais |

**`railway.json`** contém só `build.builder`, `build.dockerfilePath`,
`deploy.drainingSeconds`, `deploy.restartPolicyType` e
`deploy.restartPolicyMaxRetries`, conforme a referência atual. A regra do
Railway é que o arquivo **prevalece sobre o painel** nesses campos. Os demais
(região, réplicas, domínio, variáveis, serverless) ficam no painel.

**Por que uma réplica e sem serverless:**
- Sem roteamento por sala, duas réplicas separariam jogadores em mundos
  diferentes.
- O modo serverless dorme o serviço sem tráfego de saída e derruba a sala.

**O merge na `main` pode disparar deploy automático** (o projeto já está
ligado ao repositório). Isso consome recursos e reinicia a partida em
memória. Faça merges fora das partidas.

## Healthcheck

- O listener é um `WebSocketMultiplayerPeer` puro: uma requisição HTTP comum
  (`GET /health`) não recebe resposta HTTP 200.
- Um endpoint HTTP no mesmo `PORT` exigiria reescrever o transporte ou
  acrescentar um proxy. Por isso o Healthcheck Path fica **vazio**.

O que substitui o healthcheck:

- **Log de prontidão:**
  `DEDICATED_READY bind=0.0.0.0 port=8080 port_source=env capacity=8 protocol=11 shutdown_file=on max_rooms=12`.
  Só é impresso depois que mundo, autoridades e listener subiram sem erro.
  Falha de configuração ou bind sai com código diferente de 0, e o restart
  policy entra em ação.
- **Sonda externa com um cliente Godot real**, que faz o handshake do
  protocolo 11, entra e sai:

  ```
  godot --headless --path . -- --mode=client --probe=true --url=wss://DOMINIO
  ```

  | Resultado | Saída |
  | --- | --- |
  | Entrou | `PROBE_OK result=joined`, código 0 |
  | Sala cheia ou nome em uso | `PROBE_OK result=refused`, código 0 |
  | Versão diferente, conexão falha ou tempo esgotado | `PROBE_FAILED`, código 1 |

  Um jogador pode ver a sonda entrar e sair.

Status **Active** no Railway só diz que o processo está de pé; não prova que
um cliente consegue jogar. Quem prova é a sonda (ou o jogo) pelo domínio
público. O Railway usa o healthcheck só no início do deploy, não como
monitoramento contínuo.

## WebSocket e TLS

- **URL do cliente:** `wss://DOMINIO`, caminho `/`, porta padrão 443. Não há
  subprotocolo nem header especial.
- **TLS:** o proxy do Railway termina o TLS. O Godot valida o certificado
  público com as CAs embutidas. Não há certificado no repositório, e a
  validação não é desligada.
- **Ociosidade:** conexões WebSocket no Railway não têm limite de duração
  nem de ociosidade, segundo a documentação atual. O servidor manda
  snapshots contínuos a cada jogador na sala, então não há ping extra.
- **Conexões sem entrada:** uma conexão que não completa o handshake
  WebSocket cai em cerca de 3 s (padrão do Godot). Um WebSocket que não pede
  entrada na sala cai em 15 s (`DEDICATED_JOIN_DEADLINE`).

## Recursos medidos (local, Docker 29, 4 vCPU, container sem limite)

| Situação | CPU (% de 1 núcleo) | Memória | Rede |
| --- | --- | --- | --- |
| Vazio | cerca de 2% | 50,5 MiB | — |
| 8 clientes na rodada (parados) | cerca de 5% | 50,5 MiB | saída cerca de 2,7 MB em poucos segundos |
| Campanha de 8 clientes, 3 rodadas (tiros, coleta, mortes, reset) | média 4,8%, máx. 6% | 50,5 MiB estável | saída cerca de 25 MB em cerca de 65 s (≈ 0,4 MB/s, ≈ 1,4 GB/h com 8 jogadores) |
| Depois que todos saem | cerca de 2% | 50,4 MiB | — |

Objetos do servidor: 1450 nas três rodadas, sem crescimento.

**Limites sugeridos como ponto de partida:** 0,5 a 1 vCPU e 256 a 512 MB de
RAM. A folga é grande sobre o medido.

**Custo:**
- O tráfego de saída com 8 jogadores (≈ 1,4 GB/h) tende a pesar mais que CPU
  e RAM.
- Não há custo mensal fixo garantido, nem garantia de que créditos cubram
  qualquer uso.
- Medido fora do Railway; a CPU do Railway pode diferir.

## Logs

A saída vai para stdout e stderr. Linhas principais:

| Momento | Linhas |
| --- | --- |
| Início | `DEDICATED_START` (commit, Godot, protocolo, build, capacidade) e `DEDICATED_READY` |
| Conexões | `PEER_CONNECTED`, `CLIENT_JOINED`, `CLIENT_LEFT`, `JOIN_REFUSED` (no máximo 3 por peer) |
| Rodadas | `ROUND_STATE`, `ROUND_RESULT` |
| Periódico | `DEDICATED_STATUS` a cada 60 s: contadores (conexões, hall, salas, salas jogando, membros), RSS e objetos; sem nomes, papéis ou inventário |
| Salas | `ROOM_CREATED`, `ROOM_READY`, `ROOM_HOST`, `ROOM_REFUSED` (no máximo 3 por peer), `ROOM_JOIN_ATTEMPTS_EXCEEDED`, `ROOM_DESTROYED` (motivo `empty` ou `idle`); o código de convite nunca vai para o log do servidor |
| Encerramento | `DEDICATED_SHUTDOWN_REQUESTED`, `SERVER_SHUTDOWN_COMPLETE`, `DEDICATED_EXIT`, `WRAPPER_EXIT` |
| Falha | `DEDICATED_CONFIG_ERROR`, `DEDICATED_FATAL` |

Nenhum snapshot é logado.

| Sintoma | Onde olhar | Causa provável |
| --- | --- | --- |
| Build falhou | log de build do Railway | `FETCH_CHECKSUM_MISMATCH` ou `FETCH_RETRY` (download do Godot); `SCRIPT ERROR` na importação; export sem template |
| Binário não inicia | log do deploy | falta `DEDICATED_START`: imagem errada ou Start Command no painel sobrescrevendo o `ENTRYPOINT` |
| Recurso ausente | log do deploy | erro de `load` antes de `DEDICATED_READY`: arquivo excluído pelo preset "Linux Server" |
| Porta inválida ou ocupada | `DEDICATED_CONFIG_ERROR PORT inválida` / `DEDICATED_FATAL reason=listen_failed` | variável `PORT` mal definida |
| Serviço Active mas inacessível | sonda com `PROBE_FAILED reason=client_connection_failed` | target port do domínio diferente de `PORT`; domínio não gerado; TCP Proxy no lugar do domínio |
| WebSocket conecta mas a entrada falha | `JOIN_REFUSED reason=...` | sala cheia (`room_unavailable`), nome em uso, nome inválido |
| Protocolo incompatível | `JOIN_PROTOCOL_MISMATCH client=X server=11` | build do cliente diferente da do servidor |
| Cliente cai durante a partida | `CLIENT_LEFT` e o log do cliente | rede do jogador; redeploy (há `DEDICATED_SHUTDOWN_REQUESTED`); restart após falha (procure `DEDICATED_FATAL`) |

## Redeploy e rollback

- **Redeploy:** o deploy novo sobe primeiro. Depois, o antigo recebe SIGTERM
  e tem 15 s (`drainingSeconds`). A partida em curso termina com aviso aos
  jogadores, que voltam ao menu e entram de novo no servidor novo. O estado
  da rodada não é preservado.
- **Rollback:** no painel, aba Deployments, use "Redeploy" num deploy
  anterior que funcionava. Ou reverta o commit na `main`.

## Passos restantes no painel (a fazer por quem tem acesso)

1. **Confirmar a falha atual:** abrir o deploy com falha e anotar:
   - commit;
   - builder ("Using detected Dockerfile!" ou Railpack);
   - etapa e mensagem.

   Esta fase não teve acesso aos logs do Railway. Antes dela o repositório
   não tinha Dockerfile. Pela documentação, sem Dockerfile o Railway usa o
   Railpack, que não sabe construir um projeto Godot. Isso é uma hipótese e
   precisa ser confirmada nos logs.
2. Conferir os valores da tabela acima. Em especial: Start Command vazio,
   `PORT=8080`, domínio com target port 8080, réplica 1 e serverless
   desligado.
3. Depois do merge, acompanhar o build ("Using detected Dockerfile!",
   `FETCH_OK` duas vezes) e o log do deploy (`DEDICATED_READY ... port=8080
   port_source=env`).
4. Rodar a sonda contra `wss://DOMINIO` e esperar `PROBE_OK
   result=joined`.
5. Configurar o endpoint do cliente sem recompilar (`docs/online-endpoint.md`):
   - `--online-url=wss://DOMINIO`, ou
   - um `override.cfg` ao lado do executável com
     `network/online_url="wss://DOMINIO"`.

   Não versionar o domínio na `main` antes de ele ser validado.
6. **Teste de jogo real:**
   - 4 ou mais jogadores entram por JOGAR ONLINE;
   - jogam uma rodada completa;
   - todos saem;
   - uma nova turma entra.

   Só depois disso o modo online pode ser anunciado.

A demo Web continua offline e não se conecta a este servidor.

## Segurança operacional

- **Quem pode entrar:** qualquer pessoa que conheça o endereço pode criar
  uma sala. Para entrar numa sala é preciso o código dela, e não existe
  lista pública. Valem as regras atuais: protocolo 11, 8 vagas por sala, nome
  válido e único na sala, e validação de comandos, sequências e taxas.
  Códigos errados derrubam a conexão depois de 8 tentativas. Não há
  autenticação nesta fase.
- **Modos de teste:** não são acionáveis por clientes. Eles dependem de
  argumentos do processo, que o modo dedicado recusa, e os ganchos restritos
  a debug estão desligados no build de release.
- **Segredos:** nenhum token Railway na imagem, no repositório ou no build
  do cliente.
