# SPEC15 — lifecycle do transporte de atraso usado pelos testes

## Defeito e escopo

O helper existente `tests/net_delay_peer.gd` possuía `inner`, um MultiplayerPeer real. Os dois sinais de `inner` se ligavam a lambdas que capturavam o próprio wrapper, formando o ciclo:

`wrapper -> inner -> callable/lambda -> wrapper`.

As execuções congeladas da baseline `sync_network_rtt200/client-*.log` já terminavam com ObjectDB e `ERROR: 1 resources still in use at exit`; o harness antigo aprovava por exit/marcadores. A investigação verbose do novo fixture identificou o recurso retido como `res://tests/net_delay_peer.gd`, com MultiplayerPeerExtension, WebSocketMultiplayerPeer/WebSocketPeer e RNG. Isso é vazamento do transporte **de teste**, não mudança na autoridade ou nos clientes exportados.

A correção modifica somente o helper de testes e acrescenta `tests/net_delay_lifecycle_test.gd`. A fábrica estática `_weak_forwarder(owner: WeakRef, signal_name: String) -> Callable` captura somente a referência fraca e o nome do sinal. Enquanto o wrapper existe, o sinal é encaminhado uma vez; depois de liberado, `get_ref()` retorna null e o callback não faz nada. A fábrica é estática para não capturar implicitamente a instância.

Não foram alterados os perfis, delays, filas FIFO, ordem, seed, jitter, stalls, transferência ou serialização de pacotes. O teardown explícito do novo fixture continua inofensivo, mas a prova abaixo usa o harness antigo, sem depender dele.

## TDD e resultados

1. Escrito o teste de lifecycle para todos os sete perfis, com inner mantido vivo. Ele verifica encaminhamento de conexão/desconexão exatamente uma vez, valores originais de upstream/downstream/jitter, liberação do wrapper e silêncio dos sinais tardios.
2. **RED real antes da alteração do helper:** `NET_DELAY_LIFECYCLE_TEST_FAILED failures=14 checks=42`, exit1. Em cada perfil, falharam as duas condições relevantes: wrapper ainda retido e sinais tardios ainda encaminhados. O próprio teste desconecta os callbacks antigos somente **depois** dessas assertivas para não vazar recursos na execução RED.
3. Substituídos os dois callbacks fortes pela fábrica de WeakRef.
4. **GREEN:** `NET_DELAY_LIFECYCLE_TEST_OK checks=42`, exit0, sem SCRIPT/Parse/ERROR/ObjectDB.
5. Regressão original: `NETCODE_TEST_OK checks=266`, exit0, sem erros ou ObjectDB.
6. Transporte real original: `SYNC_NETWORK_TEST_OK profile=rtt200 seed=1 stall=false`, servidor+4 clientes, exit0. Todos os quatro logs dos clientes atuais e do servidor ficaram sem SCRIPT/Parse/ERROR/ObjectDB, incluindo encerramento — o vazamento observado na baseline desapareceu sem modificar seu harness.

Comandos, usando o env homologado Godot4.4.1:

```sh
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
"$GODOT_BIN" --headless --path . --script tests/net_delay_lifecycle_test.gd
"$GODOT_BIN" --headless --path . --script tests/netcode_test.gd
TEST_PORT=43015 PROFILE=rtt200 SEED=1 \
  TEST_LOG_DIR=/workspace/.ossuspeitos-state/phase2/net-delay-cleanup/sync-rtt200 \
  bash tests/sync_network_test.sh
```

Logs completos em `/workspace/.ossuspeitos-state/phase2/net-delay-cleanup/`: `red.log`, `green.log`, `netcode.log`, `sync-rtt200.log` e logs por peer no subdiretório. Inspeção de nove arquivos identificou zero erros inesperados ou avisos ObjectDB. O arquivo `old-build.log` é o teste negativo já existente de incompatibilidade e contém **exatamente o ERROR esperado** `JOIN_REJECTED id=old-build reason=protocol_version`; ele não é erro do cliente atual, não foi suprimido nem contado como ausência de erros no teste negativo.

O RTT200 continuou medindo aproximadamente103.4ms por sentido, devido à quantização do polling; é atraso na aplicação sobre TCP loopback. Não se alega mudança de latência ou simulação de perda física.

Após o fim, auditoria `/proc` por executável homologado e argumentos da porta43015 encontrou **zero processos Godot próprios vivos**, sem limpeza externa. Não houve alteração de produção, commit, push, merge ou publicação neste trabalho delegado.
