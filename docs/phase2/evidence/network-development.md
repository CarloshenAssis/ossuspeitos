# Fase2 — desenvolvimento do harness de transporte real

## Escopo e arquivos

Fixture novo: `tests/phase2_network_peer.gd`, cena `tests/scenes/phase2_network.tscn`, wrapper `tests/phase2_network_test.sh` e verificador de lifecycle `tests/phase2_network_wrapper_test.sh`. Nenhum arquivo de produção alterado por este trabalho. O fixture herda NetworkApp de produção; as duas RPCs de instrução/observação existem apenas no subclass em `tests/`. Não são usados para certificar índices de handshake de uma build exportada.

Servidor e todos os clientes utilizam a mesma cena e o transporte WebSocket real. As ações passam pelos helpers de intenção/previsão, pacote de comandos, fila, epoch/gate e autoridades de produção. Preparação de posição/arma é feita apenas no servidor do fixture. Não há chamada direta de dano/eliminate/end para fabricar vitória: os corpos e o fim da rodada provêm dos tiros aceitos.

## Sequência comprovada

Cada rodada verifica:

- Porta fecha/abre por intenção real e todos os clientes recebem seu estado. Cada cliente compara os bloqueadores instalados na previsão com os derivados de seu snapshot sanitizado.
- O mesmo tiro oficial em porta fechada deixa o alvo com100 de vida; aberto reduz para66. Movimento comandado é contido na porta fechada e cruza o vão aberto.
- Dois clientes disputam a mesma prop: exatamente um pedido aceito e um holder. O teste espera o objeto realmente elevar-se antes de soltar; espera repouso e evento autorizado de impacto. Empurrar produz deslocamento.
- Intenção fora de alcance e replay são recusados. A primeira não altera o buffer sonoro; há exatamente dois eventos de porta para as duas mudanças aceitas.
- Passos decorrem de deslocamento oficial real na passagem aberta; recarga aceita gera seu evento e termina pelo relógio do servidor.
- Tiros aceitos eliminam a vítima ferida enquanto a rodada ainda está ACTIVE. Todos recebem um corpo; dois vivos o inspecionam independentemente, cada um recebe apenas seu próprio DTO sanitizado. Clientes que não solicitaram continuam com inspeção vazia.
- Um pedido de inspeção de morto é enviado como pacote real hostil e recusado pelo gate `player_dead`; um vivo distante recebe `out_of_range`.
- Mais três tiros aceitos eliminam o adversário e encerram a rodada. Todos recebem os dois corpos. Na campanha, a próxima rodada exige corpos/inspeção vazios e porta restaurada antes de repetir tudo.

Instruções só enfileiram ações quando rodada e epoch recebidas coincidem com o estado oficial preparado pelo servidor e `_commands_enabled()` está aberto. Observadores mortos não precisam ter controles habilitados para confirmar estado público. ACKs de barreira são correlacionadas por stage e conexão, com uma confirmação por peer.

## Resultados executados

Godot4.4.1 homologado, headless, fonte do env `/workspace/.ossuspeitos-state/mission-sdd/env.sh`. As alterações do SPEC12 estavam na árvore de trabalho; o JSON registra o HEAD de desenvolvimento, sem atribuir esta execução a um commit final posterior.

| Comando (com GODOT_BIN do env) | Resultado |
| --- | --- |
| `TEST_PORT=42619 PROFILE=local PHASE2_CLIENTS=4 PHASE2_ROUNDS=1 bash tests/phase2_network_test.sh` | PASS:28 assertivas de servidor,1 marcador de rodada,4 marcadores de cliente, todos exit0 |
| `TEST_PORT=42617 PROFILE=rtt200 PHASE2_CLIENTS=4 PHASE2_ROUNDS=1 bash tests/phase2_network_test.sh` | PASS:28 assertivas de servidor,1 rodada,4 clientes exit0 |
| `TEST_PORT=42618 PROFILE=local PHASE2_CLIENTS=8 PHASE2_ROUNDS=3 bash tests/phase2_network_test.sh` | PASS:84 assertivas de servidor,3 rodadas,8 clientes exit0 |
| `bash tests/phase2_network_wrapper_test.sh` | PASS:falha37 preservada; TERM143 preservado; processos diretos do fixture falso reaproveitados por exec e todos encerrados/reaped |
| `bash -n tests/phase2_network_test.sh tests/phase2_network_wrapper_test.sh` | PASS |

As três execuções de gameplay passaram o gate `SCRIPT ERROR|Parse Error|^ERROR:` sem ocorrências. Todos os processos terminaram pelo handshake de produção. Auditoria `/proc` por executável Godot homologado e argumento da cena nova encontrou **zero processos próprios vivos**, sem limpeza externa.

RTT200 é atraso de aplicação de100ms em cada direção, sobre WebSocket/TCP loopback, não perda física de pacotes. As assertivas de observação de todos os peers estão nas barreiras; o número28/84 conta os marcadores explícitos do servidor, não todas as comparações por quadro/cliente.

Evidência estruturada: [network-development-summary.json](network-development-summary.json). Logs completos externos em `/workspace/.ossuspeitos-state/phase2/network-dev/{local-final,investigation,eight-final}/` e respectivos arquivos `network-dev-*.log`. A execução RTT200 de desenvolvimento usou `--verbose` para confirmar teardown; as finais local/8 usam saída normal. O resumo não declara CI remoto, builds ou playtest humano aprovados.

## Falhas encontradas durante desenvolvimento

1. RED inicial: a cena obrigatória não existia (`test -f tests/scenes/phase2_network.tscn`, exit1). O primeiro fixture executável foi implementado e rodado em seguida.
2. O primeiro cenário exigia passo em apenas~0.4m antes da porta, abaixo da cadência oficial0.65m: timeout legítimo do fixture. A assertiva de passo foi deslocada para o movimento real atravessando a porta aberta; a colisão fechada continua exigida.
3. A posse podia ser ganha por qualquer contendendor, cuja orientação original deixava o alvo de carry bloqueado. Isso fazia o teste supor uma queda sem ter elevado o objeto. Os dois contendores agora olham para área livre e há barreira de altura>1m antes de drop, comprovando queda real em vez de fabricar o som.
4. Uma tentativa8×3 iniciou durante edição incompleta do SPEC12 e falhou no gate de compilação; não foi contada como aprovação. A matriz acima foi executada após o código estar estável.
5. O strict gate revelou um vazamento **preexistente do transporte de teste**: `tests/net_delay_peer.gd` conectava sinais de `inner` a lambdas que retinham o wrapper, enquanto o wrapper possuía `inner`. Confirmado em verbose como GDScript `net_delay_peer.gd`, MultiplayerPeerExtension, WebSocket peer e RNG ainda retidos. Os logs da baseline congelada `sync_network_rtt200/client-*.log` já contêm o mesmo ObjectDB/**ERROR1resource**; o PASS desse harness antigo era por exit/marcadores, não por ausência de erros de encerramento.

O fixture novo não enfraquece o gate nem modifica o transporte antigo: no seu `_exit_tree` desconecta os forwarders de seu próprio `inner`, fecha/libera wrapper e chama o cleanup herdado. Assim a execução RTT200 nova tem zero ERROR. Uma correção geral do transporte antigo pertence a uma tarefa separada com regressão própria; não é declarada concluída por este teardown de fixture.

## Limites

Esta cena cobre uma sala local por servidor; não certifica, sozinha, isolamento de transporte entre salas online. Manter as suítes existentes de salas/adversários/resiliência e o fixture unitário de duas MatchRooms. Inspeções usam corpos de mortes por tiros reais, mas reentrada/reconexão online ativa depende da política existente que bloqueia entrada durante partida.

Áudio aqui significa evento autorizado, sanitização, origem e contagem no transporte; não percepção estéreo humana. Deduplicação/reprodução espacial, volumezero, oclusão, lifecycle de áudio e animação30/60/120FPS pertencem às respectivas suítes e smoke gráfico. Não há certificação de GPU física nem de efeitos gráficos pelo headless.
