# SPEC16 — desenho do teste multiprocesso da Fase 2

Pesquisa sobre as APIs reais, sem implementação de runtime. O SPEC09 ainda estava em desenvolvimento durante esta leitura; o executor deve conferir os nomes finais antes de escrever o teste. Este documento não é evidência de teste executado.

## Estrutura recomendada

- `tests/phase2_network_peer.gd`: `extends "res://shared/network_app.gd"`, usado **por todos** os processos do harness. Acrescenta apenas o coordenador e RPCs de barreira do teste.
- `tests/scenes/phase2_network.tscn`: raiz `NetworkApp`, script acima. Iniciar Godot com esta cena em vez da cena principal. A classe de produção e todos os seus RPCs continuam herdados.
- `tests/phase2_network_test.sh`: inicia um servidor e 4 ou 8 clientes, registra PIDs, impõe watchdog, exige saída0 de todos e marcador final em cada processo. Executar local e RTT200; para oito jogadores repetir três rodadas reais.
- Teste unitário separado com duas instâncias `MatchRoom` cobre isolamento do estado e cópias. Não declarar isolamento de transporte provado apenas por esse teste; manter os harnesses de salas existentes e adicionar uma execução com salas online quando viável.

O script derivado não deve sobrescrever nenhum método `@rpc` de produção. Observar `local_environment`, `local_bodies`, `local_round_public`, `prediction` e futuros campos de áudio/investigação em `_process` depois de `super._process(delta)`. Isso evita dúvida sobre herança de configuração RPC/índices. Para observar resultados de servidor, sobrescrever o método não-RPC `_report_action_result(peer_id, kind, id, result)`, chamar `super` e guardar cópia. Para observar o pedido antes/depois, outro ponto não-RPC existente é `_run_command_action`; preferir o primeiro.

As novas RPCs do subclass existem apenas em `tests/`, com o mesmo script em todos os peers. Não adicionar hooks/flags/RPCs ao runtime de produção nem usar este subclass para certificar compatibilidade de handshake entre builds diferentes; esta continua coberta pelo teste de protocolo da cena de produção.

## APIs observadas

- Intenção humana: `queue_environment_interaction(verb: String, object_id: String = "") -> bool`.
- Transporte real: previsão -> `_client_command_tick()` -> `NetSync.encode_action` -> `submit_commands` -> gate/epoch/fila -> `_run_command_action` -> `InteractionAuthority.request`.
- Autoridade por sala: `default_room.interactions`, `interaction_authority.snapshot()`, `object_state(id)`, `world.states`, `world.teleport(peer,position,yaw,pitch)`.
- Estado cliente: `local_environment`, `prediction.environment_blockers`, `prediction.epoch`, `_commands_enabled()`, `local_round_public`, `local_combat_state` e `local_bodies`.
- Disparo/coleta: `_queue_local_action(NetSync.ACTION_PICKUP,pickup_id)` e `_queue_local_action(NetSync.ACTION_FIRE)`, somente após `_commands_enabled()`; não usar `request_fire` diretamente no coordenador.
- Encerramento: `_begin_server_shutdown(lobby.peer_ids())` e handshake existente. Antes dele, exigir todas as barreiras e imprimir marcador da campanha; cada cliente imprime seu marcador ao receber `test_finish` antes do shutdown de produção.

**Problema encontrado na API em desenvolvimento:** `queue_environment_interaction` exige `arena_view != null` mesmo com alvo explícito. Clientes headless não têm ArenaView; ajustar o helper para exigir a view **apenas** ao resolver alvo vazio. Não criar ArenaView só para contornar isso nem tratar um teste que não enfileira interação como aprovado. Se o contrato final deliberadamente mantiver o helper apenas gráfico, o fixture pode usar `prediction.queue_action` com o mesmo DTO e contador oficial, mas deve registrar que o caminho humano não foi coberto pelo teste headless.

## Duas RPCs de teste e uma barreira

```gdscript
@rpc("authority", "call_remote", "reliable")
func test_instruction(stage_id: int, instruction: Dictionary) -> void:
    # Guardar, não executar imediatamente; aguardar epoch e rodada.

@rpc("any_peer", "call_remote", "reliable")
func test_observation(stage_id: int, observation: Dictionary) -> void:
    # Remetente vem da conexão; só membro esperado, stage atual, uma ACK.
```

Instrução fechada do teste: `{round_id, epoch, operation, target, expected}`; não vira entrada de produção. Antes de executar intenção, o cliente deve observar `local_round_public.round_id == round_id`, `prediction.epoch == epoch` e `_commands_enabled()`. Teleporte oficial incrementa epoch: este é o mesmo risco que produziu a corrida de fila/epoch na fase anterior. Nunca considerar um `rpc_id` enviado como ação aceita.

Observações são calculadas sobre o estado recebido, nunca apenas eco do `expected`. Exemplo de fechamento: o cliente localiza a porta em `local_environment.objects`, verifica `open == false`, verifica o AABB correspondente em `EnvironmentRules.blockers(local_environment)` e sua própria previsão, então confirma `{object_id, open, round_id, revision}`. O servidor exige todos os peers, mesma rodada, revisão pelo menos a da mutação; ignora ACK duplicada/antiga. Para objetos em queda não exigir igualdade da revisão/posição entre snapshots de ticks distintos: esperar repouso e usar tolerância explícita, por exemplo0.02m.

Timeout é por etapa e imprime etapa/peers faltantes/resultados/épocas, sem papéis. Não prolongar timeout para mascarar ações que nunca foram enfileiradas.

## Sequência mínima por rodada

| Etapa | Preparação somente no servidor de teste | Ação por cliente/transporte real | Assertiva independente |
| --- | --- | --- | --- |
| ACTIVE | Esperar 4/8 participantes e inventário inicial | Todos esperam primeiro ACK/época da rodada | Todos recebem ambiente completo sanitizado, corpos vazios, sem reveal |
| DOOR_CLOSE | Posicionar ator1 em ponto livre perto da porta0; demais fora do vão | `toggle` | Autoridade fechada, ACK de todos, mesma caixa em movimento/tiro/previsão |
| DOOR_BLOCK_MOVE | Orientar ator para atravessar o vão | Roteiro de comandos60ticks movendo, depois ZERO | Posição oficial para antes do volume; não atravessa nem em RTT200 |
| DOOR_OPEN | Reposicionar perto, esperar nova época | `toggle`, depois mesmo roteiro | Caixa desaparece; movimento cruza o vão; todos veem estado aberto |
| PROP_CONTEST | Posicionar dois vivos próximos da prop leve, sem colisão inicial | Ambos `take` em barreira única | Exatamente um resultado aceito, holder único; os dois não ganham posse |
| PROP_DROP | Holder permanece próximo e estável | `drop` | holder0 em todos; queda/impacto autorizados; repouso no piso e sem atravessar jogador |
| PROP_PUSH | Ator próximo em direção desobstruída | `push` | Deslocamento positivo limitado, velocidade dentro do catálogo; snapshots convergem |
| REJECT | Ator4 longe, outro morto posteriormente | Intenção fora de alcance; replay com mesmo id; payloadforjado adicional | Recusa específica e mundo inalterado; nenhum som de sucesso/evento global novo |
| COMBAT | Preparar faixa livre e arma/munição oficial no mapa por fixture | Coletar, disparar, recarregar, disparar até morte de uma vítima | Dano34 por tiro, corpo oficial único; eventos de tiro/recarga só de ação aceita |
| INVESTIGATE | Manter rodada ACTIVE: vítima eliminada deve deixar outros inocentes vivos | Dois vivos inspecionam corpo via intenção de investigação final | Resposta permitida individual; morto/distante recusado; sem papel/autor/inventário |
| ROUND_END | Roteiro de combate elimina assassino via tiros aceitos | Ações cruzam submit_commands | Reveal só depois ENDED, nenhum evento antigo reaplicado |
| ROUND_RESET | Esperar reset/countdown/ACTIVE seguinte | Todos esperam nova época | Portas abertas/defaults, props restauradas, holder0, corpos/inspeções/eventos antigos limpos |

Para cenário determinístico, escolher a vítima e o assassino **no servidor**, sem divulgar o mapa de papéis no test_instruction nem logs dos clientes. Não colocar todos os alvos na mesma linha de tiro. Preparação oficial pode mover pickups ao ator, como o harness de combate existente; a coleta e os tiros continuam intenções reais. Não matar diretamente só para afirmar que o tiro/áudio foi testado.

A primeira porta é `porta_escritorio_leste`, centro aproximado `(6.25,1.2,2.5)`, volume0.5×2.4×2. Ponto candidato `(5.25,1,2.5)` olhando+X permite testar a passagem, mas confirmar com `ArenaRules.overlaps_blocker` e catálogo final antes de fixá-lo. Não confiar em coordenadas não verificadas. O teste de porta bloqueando tiro deve colocar um alvo atrás do vão e repetir o mesmo disparo fechado/aberto, observando saúde e endpoint; não basta testar `EnvironmentRules.first_hit` isoladamente.

## Áudio e visual

Usar a API final do SPEC10: observar evento autorizado com id/rodada/kind/posição e o estado de deduplicação do controlador; não enviar evento falso por RPC de teste e contar reprodução como validação de autorização. Exigir um único evento/reprodução por cliente para porta/impacto/tiro/recarga e nenhum para a interação recusada. Passos precisam de movimento oficial real. Em headless testar autorização/DTO/deduplicação, não alegar percepção estéreo humana; um smoke gráfico separado instancia ArenaView/AudioStreamPlayer3D com driver Dummy e confirma limites/lifecycle.

Ações visuais do SPEC11 podem ser observadas no smoke gráfico lendo o estado/pivôs depois dos mesmos eventos. Unidade30/60/120FPS deve fixar duração/pose e garantir raiz/mira/estado oficial intactos; processo headless sozinho não certifica qualidade visual.

## Matriz executável sugerida

1. `PHASE2_CLIENTS=4 PHASE2_ROUNDS=1 PROFILE=local bash tests/phase2_network_test.sh`.
2. `PHASE2_CLIENTS=4 PHASE2_ROUNDS=1 PROFILE=rtt200 bash tests/phase2_network_test.sh` (100ms por direção na aplicação/TCP, não perda física).
3. `PHASE2_CLIENTS=8 PHASE2_ROUNDS=3 PROFILE=local bash tests/phase2_network_test.sh`.
4. Unidade com duas MatchRooms, snapshot/revisão/posse/eventos de uma sala inalterados após ações na outra; repetir os harnesses online de salas/adversários/resiliência existentes.
5. Regressão completa e smoke gráfico; Web/Windows/container remotos permanecem jobs de produção, sem publicação.

Não declarar reconexão validada apenas por um novo snapshot na mesma conexão: incluir desconexão real e reconexão de um cliente no lobby, ou manter o harness de resiliência e marcar investigação ativa/reentrada como limitada pela regra atual que bloqueia entrada online durante rodada.

## Lifecycle do wrapper

Guardar cada PID direto do processo Godot; usar `exec` em helpers de processo para que `$!` não seja só um shell. Nenhum coordenador deve iniciar filhos fora do wrapper. Trap EXIT/TERM/INT preserva status original, envia TERM aos PIDs próprios e espera todos; watchdog é processo próprio também registrado/encerrado. Evitar subshell watchdog que deixa `sleep` órfão: `timeout` externo com foreground e traps do wrapper ou Timer interno de cena é mais simples. Testar interrupção143 e falha37 com processos descendentes antes de afirmar cleanup.

Logs por execução/peer, seed e portas explícitas. Exigir exit0 de servidor e cada cliente, marcador de campanha e todos os marcadores de cliente; ausência de SCRIPT ERROR/Parse Error/ERROR. Manter limite de tempo global, diagnóstico final e artifacts `always()` no CI. Não reusar porta de outro harness em paralelo.

## Riscos que o executor precisa resolver

- APIs10–12 ainda não existiam nesta pesquisa: nomes de eventbuffer/inspeção devem ser definidos antes do fixture, não inventados no relatório.
- Test-only RPCs alteram superfície do subclass; não os exportar em builds nem inferir handshake de produção a partir desse fixture.
- IDs de interação/ação reiniciam por rodada; replay por packetseq e replay por actionid são casos diferentes e ambos precisam ser exercitados.
- Comparar snapshots de ticks diferentes como se fossem simultâneos gera falsos negativos de prop em movimento.
- Dependência de áudio real, mouse capturado ou ArenaView no helper impediria os headless de enviar ações; testar caminho explícito sem apresentação.
- Um servidor+4clientes que só executa o harness antigo não certifica portas/props/investigação novos. A matriz final deve distinguir esses casos.
