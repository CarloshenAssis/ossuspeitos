# SPECs 01–08 — plano de implementação incremental

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** melhorar os sistemas existentes sem reconstruir o jogo, preservando autoridade, privacidade e os testes.

**Architecture:** `MovementRules`, `AuthoritativeWorld`, `PlayerPrediction` e `RemoteInterpolator` já formam o movimento compartilhado com previsão. `WeaponDefinition`, `InventoryAuthority`, `CombatRules` e `CombatAuthority` já formam o combate; ampliar essas fronteiras, mantendo `NetworkApp` como adaptador e `ArenaView` como apresentação. Propostas abaixo não são implementações nem autorização para alterar contratos.

**Tech Stack:** Godot 4.4.1, GDScript, WebSocket/TCP, Godot headless + Bash/Python; renderer `gl_compatibility`.

**Spec:** [master-spec-v1.md](master-spec-v1.md), versão 1.0. Base auditada: `dd15ff2ab29d5e67fccedc41c431c30eb7e32c6d`.

**Status:** plano para revisão. SPEC 01 bloqueado até aprovação explícita do SPEC 00. Cada SPEC terá branch e PR próprios; merge e deploy continuam sujeitos à aprovação humana. O SPEC 00 não altera gameplay.

## Global Constraints

- Preservar funcionalidades, contratos de rede, regras de partida e testes existentes.
- Preservar servidor autoritativo, identificação de jogadores e validação de comandos.
- Não incorporar código GPL de Quake III ou ioquake3. Estudar sua arquitetura e criar implementações independentes.
- Não importar assets de jogos ou repositórios sem verificação individual da licença.
- Nunca alterar a branch principal diretamente.
- Não modificar protocolos persistidos, snapshots ou contratos de rede sem identificar e atualizar todos os consumidores.
- Parar a integração de uma etapa se houver regressão crítica, conflito arquitetural ou licença não verificada.
- Usar PRs separados e deixar merge e deploy sujeitos a aprovação.
- Não ampliar o escopo para novas regras sociais, inventário complexo ou funcionalidades não solicitadas.
- Protocolo efetivo 11, tick de 60 Hz, input em lotes a 30 Hz, snapshots a 20 Hz. Preservar esses valores por padrão; qualquer mudança precisa de decisão, comparação e teste de versão incompatível.

## Review Focus

1. Entrada não finita, configuração adulterada e velocidade acima do limite: servidor rejeita sem contaminar previsão — SPEC 01.
2. ACK antigo, época trocada no reset e perda de foco com input pendente: nenhuma ação residual, crescimento ilimitado ou teleporte involuntário — SPEC 02.
3. Dois tiros no mesmo tick e duplicação de uma ação: dano/consumo no máximo uma vez, resolução determinística documentada — SPEC 03.
4. Efeito visual ou interpolação atravessando parede e alterando mira: separar transformação oficial da apresentação — SPECs 04–05.
5. Jogador desconectado ou eliminado durante troca de rodada/sala: sem vazamento de papel, inventário, corpo ou comandos entre épocas/salas — SPECs 07–08.

## Como executar cada tarefa futura

A unidade de entrega é o SPEC, não cada pequena modificação. Cada tarefa abaixo segue o mesmo ciclo, na branch daquele SPEC: escrever o caso de regressão no arquivo indicado; executar e demonstrar a falha específica; implementar o mínimo na fronteira indicada; repetir o teste e os checks da [matriz](test-matrix.md); registrar comandos, marcadores, métricas, origem/licença e limitações; commit; PR; aguardar aprovação. Não remover assertivas existentes para obter aprovação. As novas suítes e os novos nomes de testes indicados abaixo são **propostos**, ainda inexistentes; não representam resultados do SPEC 00.

Convenções para os comandos (partindo da raiz do checkout):

```bash
export GODOT_BIN=/workspace/.ossuspeitos-tools/Godot_v4.4.1-stable_linux.x86_64
export XDG_CONFIG_HOME=/workspace/.ossuspeitos-state/config
export XDG_CACHE_HOME=/workspace/.ossuspeitos-state/cache
export XDG_DATA_HOME=/workspace/.ossuspeitos-state/data
"$GODOT_BIN" --headless --path . --editor --quit
```

Saída zero isolada não basta: exigir marcador final da suíte, confirmar que as assertivas foram executadas e inspecionar `SCRIPT ERROR`/`Parse Error`. Conservar os logs fora da árvore de fontes e anexar as evidências ao PR. Comparações antes/depois usam mesma versão, mapa, seed, perfil de rede, resolução e recursos da máquina; nunca comparar medições históricas como se fossem contemporâneas.

Contrato proposto das novas suítes: cada script GDScript abaixo é `extends SceneTree`, termina com `quit(0)` apenas após todas as assertivas e imprime o marcador exato. Em falha, imprime um diagnóstico com caso/esperado/observado e termina com `quit(1)`.

| Nova suíte proposta | Marcador exigido |
| --- | --- |
| `tests/movement_config_test.gd` | `MOVEMENT_CONFIG_TEST_OK` |
| `tests/role_damage_rules_test.gd` | `ROLE_DAMAGE_RULES_TEST_OK` |
| `tests/gunplay_test.gd` | `GUNPLAY_TEST_OK` |
| `tests/camera_effects_test.gd` | `CAMERA_EFFECTS_TEST_OK` |
| `tests/graphics_profiles_test.gd` | `GRAPHICS_PROFILES_TEST_OK` |
| `tests/gameplay_integration_test.sh` | `GAMEPLAY_INTEGRATION_TEST_OK clients=4` (mais campanha existente com 8) |

Comando unitário completo para cada caminho `.gd` nomeado nas verificações: `"$GODOT_BIN" --headless --path . --script CAMINHO`. Novos `.sh` recebem `GODOT_BIN="$GODOT_BIN"` e preservam saída do processo/harness; uma execução sem casos não conta como aprovação.

## SPEC 01 — movimento configurável, sem substituição do controlador

**Já existe:** WASD normalizado, aceleração/parada, colisão analítica subdividida com deslizamento por eixo e integrador reproduzido no servidor e cliente. `MovementRules.MAX_SPEED=5.0`, `ACCELERATION=18.0`; posição oficial tem `y=PLAYER_HEIGHT=1.0`.

**Lacuna e decisão necessária:** não há salto, gravidade, ar, sprint, rampas ou estado grounded. Eles não cabem no pacote atual sem definir novos comandos e simulação vertical. A aprovação do SPEC 00 não define velocidades novas nem autoriza trocar colisão analítica por `CharacterBody3D`. Dividir SPEC 01 em parametrização compatível e extensão vertical condicionada à decisão de design, ambas dentro de PRs rastreáveis ao SPEC. Não declarar o SPEC completo omitindo essa decisão.

**Arquivos:** modificar `shared/movement_rules.gd`, `shared/game_controls.gd`; criar `shared/movement_config.gd` e `tests/movement_config_test.gd`; ampliar `tests/movement_rules_test.gd`. Somente após decisão vertical: `shared/net_sync.gd`, `shared/player_prediction.gd`, `server/authoritative_world.gd`, `shared/network_app.gd`, `shared/arena_rules.gd`, `client/arena_view.gd` e respectivas suítes.

**Interfaces:** manter `MovementRules.validate_input(move: Vector2, yaw_delta: float, pitch_delta: float = 0.0) -> String`, `simulate_command(state: Dictionary, move: Vector2, yaw_delta: float, pitch_delta: float) -> String` e `resolve_step(from: Vector3, step: Vector3) -> Dictionary`. Proposta de `MovementConfig extends Resource`: `walk_speed: float = 5.0`, `ground_acceleration: float = 18.0`, `ground_deceleration: float = 18.0`, `validate() -> String`. O servidor carrega e valida o recurso; cliente não escolhe valores. Se configuração precisar viajar ao cliente para replay, projetar handshake versionado e listar consumidores antes de editar o fio.

- [ ] Registrar decisão em `docs/decisions.md`: parametrização inicial mantém os defaults atuais; especificar separadamente limites de sprint, impulso de salto, gravidade, inclinação máxima e ar, ou registrar decisão de adiamento aprovada.
- [ ] Acrescentar `test_defaults_preserve_replay`, `test_diagonal_speed_bound`, `test_stop_deceleration`, `test_non_finite_config_rejected`: replay com defaults igual ao baseline, velocidade ≤5.0, parada monotônica, NaN/INF e valores não positivos rejeitados. Executar antes da implementação e guardar a falha esperada da configuração inexistente.
- [ ] Implementar a configuração validada e seu uso por servidor/previsão sem criar outro `MovementController`. Não permitir editar estado autoritativo por RPC.
- [ ] Depois da aprovação do movimento vertical, adicionar testes `test_jump_landing`, `test_air_control_bound`, `test_slope_limit`, `test_sprint_returns_to_walk`, `test_old_epoch_cannot_jump` com os valores exatos aprovados; só então estender comandos, simulação e snapshots. Migrar todos os consumidores juntos se mudar o protocolo.
- [ ] Executar `"$GODOT_BIN" --headless --path . --script tests/movement_config_test.gd`, `tests/movement_rules_test.gd`, `tests/netcode_test.gd` e `GODOT_BIN="$GODOT_BIN" ./tests/network_smoke_test.sh`; exigir novos marcadores mais `MOVEMENT_RULES_TEST_OK`, `NETCODE_TEST_OK` e o marcador final do harness. Registrar defaults e métricas; commit e PR.

## SPEC 02 — comprovar e melhorar a previsão existente

**Já existe:** comandos com sequência/época, ACK, replay puro, buffer limitado, recuperação, suavização local, interpolação remota e instrumentação. Seria duplicação criar um novo `PredictionBuffer`, `ReconciliationController` ou `RemoteInterpolation` paralelo.

**Arquivos:** ampliar `tests/netcode_test.gd`, `tests/net_delay_peer.gd`, `tests/sync_network_test.sh`, `tests/sync_network_coordinator.gd`; alterar `shared/player_prediction.gd`, `client/remote_interpolator.gd`, `server/authoritative_world.gd` ou `shared/net_sync.gd` somente se as novas medições/casos identificarem deficiência. Documentar em `docs/netcode.md`.

**Interfaces:** preservar `PlayerPrediction.build_command(move: Vector2) -> Dictionary`, `reconcile(ack: Dictionary, player: Dictionary) -> Dictionary`, `presented(fraction: float, delta: float) -> Dictionary`, `RemoteInterpolator.push(tick: int, players: Array) -> bool`, `advance(delta: float) -> void`, `sample(peer_id: int) -> Dictionary`; `NetSync.encode_packet(epoch: int, first_seq: int, commands: Array) -> Array`.

- [ ] Estender o harness com perfis nomeados `rtt50`, `rtt100`, `rtt200` (25/50/100 ms por sentido, sem jitter) além de `local`, mantendo `rtt80`, `rtt150j` e `STALL=true`. Documentar que os perfis atuais atrasam entrega de aplicação FIFO sobre TCP: não emulam perda/reordenação física.
- [ ] Acrescentar casos `test_epoch_reset_discards_pending_action`, `test_out_of_order_ack_does_not_rewind`, `test_pending_limit_recovers`, `test_duplicate_input_single_step`; afirmar fila servidor ≤32, pendentes cliente ≤90, amostras remotas ≤32 e descarte de época antiga. Usar relógio/seed injetados para algoritmos, sem sleeps nas assertivas unitárias.
- [ ] Criar cenário separado de falha de transporte: perda/reordenação no teste da fila de comandos em processo; para perda TCP real medir atraso/retransmissão e bloqueio do fluxo, sem alegar que um `unreliable` RPC elimina TCP head-of-line. Manter transporte de produção.
- [ ] Medir baseline antes de alterar algoritmos: erro posição/yaw/pitch p50/p95/máximo, tempo até convergir, correções pequenas/grandes, idade dos pendentes, fila e snapshots recebidos. Convergência após parar ≤ `NetSync.CONVERGENCE_DEADLINE_SECONDS=1.0`; nenhuma extrapolação acima de 6 ticks. Fixar no PR o orçamento numérico de melhoria antes de mudar a implementação; ausência de erros não é métrica de sucesso.
- [ ] Corrigir apenas falhas demonstradas; repetir `tests/netcode_test.gd` e `PROFILE=<perfil> SEED=1 GODOT_BIN="$GODOT_BIN" ./tests/sync_network_test.sh` para local/50/100/200 ms e jitter. Exigir `SYNC_NETWORK_TEST_OK` com perfil/seed corretos, testes adversariais e comparação antes/depois. Commit e PR sem tradução de GPL.

## SPEC 03 — modularidade do combate existente

**Já existe:** catálogo validado, inventário, pickup, munição, recarga, cadência, sequências, hitscan, dano, eliminação e evento público sanitizado. A pistola comum é `common_pistol`: dano 34, pente 6, reserva máxima 18, intervalo 400 ms, alcance 20 m, recarga 1200 ms, spread zero. Não criar um segundo `WeaponController` para essas responsabilidades.

**Lacuna de regras:** o combate atual aplica dano comum independentemente do papel. Armas especiais do assassino/detetive e consequência de atingir inocente não estão implementadas; precisam de tabela de comportamento explicitamente aprovada. Não fazer essa alteração passar por mera refatoração.

**Arquivos:** modificar `server/combat_authority.gd`, `server/combat_rules.gd`, `server/inventory_authority.gd`, `shared/weapon_definition.gd`/`weapon_rules.gd` apenas quando necessário; propor `server/role_damage_rules.gd` e `tests/role_damage_rules_test.gd` após aprovação das regras. Ampliar `tests/combat_authority_test.gd`, `tests/combat_rules_test.gd`, `tests/weapon_rules_test.gd`, `tests/combat_network_coordinator.gd`.

**Interfaces:** preservar `CombatAuthority.request_fire(peer_id: int, sequence: Variant, now_msec: int) -> Dictionary`, `request_reload(...)`, `private_state(peer_id: int) -> Dictionary`, sinais `shot_resolved(event: Dictionary)`/`private_state_changed(peer_id: int, state: Dictionary)` e `RoundAuthority.eliminate_player(peer_id: int, cause: String, instigator_peer_id: int = 0, now_msec: int = -1) -> String`. Proposta de resolução de papel independente: `RoleDamageRules.resolve(shooter_role: int, target_role: int, weapon_id: String) -> Dictionary`; a allowlist do resultado e as regras exatas são fixadas pela tabela aprovada antes da implementação. Nunca serializar papéis no evento público.

- [ ] Acrescentar primeiro casos de fronteira: sem arma, pente vazio, recarga, morto, cooldown, parede, alcance, sequência repetida e dois tiros simultâneos. Assertivas atuais da pistola comum permanecem 34/6/400/20/1200.
- [ ] Verificar em `test_same_tick_shots_order` a ordenação autoritativa escolhida e em `test_duplicate_shot_consumes_once` munição/dano exatamente uma vez; reproduzir com seed/tick fixos antes de refatorar.
- [ ] Isolar catálogo e aplicação de dano somente onde a evidência de extensibilidade justificar. Hitscan continua analítico contra `ArenaRules`; não introduzir projétil sem arma aprovada que o exija.
- [ ] Aprovar tabela para arma especial (detetive × assassino, detetive × inocente, assassino × alvo), disponibilidade e destino do atirador/alvo; escrever os testes da tabela antes do módulo. Ressurreição, economia e novos estados sociais ficam fora deste framework.
- [ ] Rodar suítes de armas, inventário, combate e rodadas; executar `GODOT_BIN="$GODOT_BIN" ./tests/combat_network_test.sh` e `COMBAT_CLIENTS=8 COMBAT_EXTENDED=true GODOT_BIN="$GODOT_BIN" ./tests/combat_network_test.sh`. Exigir marcador com contagem/configuração correta, sigilo e encerramento coordenado; commit e PR.

## SPEC 04 — calibração de spread/recoil, sem framework paralelo

**Já existe:** `WeaponDefinition.spread_radians`, RNG injetável em `CombatRules`, alcance configurável, hitscan oficial e recoil visual em `ArenaView._recoil()`. Separar calibração de introdução de novas armas.

**Arquivos:** ampliar `shared/weapon_definition.gd`, `shared/weapon_rules.gd`, `server/combat_rules.gd`, `server/combat_authority.gd`, `client/arena_view.gd`, `client/combat_fx.gd`; criar `tests/gunplay_test.gd`, `tests/scenes/gunplay_lab.tscn` e `docs/gameplay-research/04-calibration.md`. Preservar a pistola comum por padrão; a cena de laboratório não substitui a mansão.

**Interfaces:** preservar `CombatRules.request_shot(peer_id: int, intent: Variant, context: Variant, now_msec: int) -> Dictionary` e `_apply_server_spread(direction: Vector3, spread_radians: float) -> Vector3`; servidor controla RNG. Usar `shot_resolved` para efeitos, nunca para aceitar seed/impacto vindos do cliente. Qualquer campo de precisão/recoil novo no catálogo é validado por `WeaponRules.validate_definition(definition: Variant) -> String` antes de uso.

- [ ] Fixar configuração de calibração no documento: spread em repouso/movimento, recuperação e primeiro tiro; defaults zero preservam a arma comum. Se houver recoil lógico que altere mira oficial, aprovar como mudança de simulação e testar replay no SPEC 02; recoil visual fica fora dela.
- [ ] Acrescentar `test_same_seed_same_trajectory`, `test_client_seed_rejected`, `test_range_endpoint`, `test_wall_before_target`, `test_visual_recoil_does_not_change_hit`, `test_recovery_uses_server_time`; rodar e observar a falha da funcionalidade proposta antes da implementação.
- [ ] Implementar calibração no catálogo existente e relógio/RNG servidor; sem penetração, destruição, runtime externo ou projétil especulativo. Identificar superfícies por dados públicos do mapa se os efeitos exigirem; alterar DTO apenas com versão/consumidores revisados.
- [ ] Rodar `"$GODOT_BIN" --headless --path . --script tests/gunplay_test.gd`, combate, netcode e cenário multiprocesso. Comparar mesma seed/arma/distância antes/depois e provar resultado único servidor reproduzido pelos clientes; commit e PR.

## SPEC 05 — câmera FPS e apresentação

**Já existe:** yaw/pitch, câmera local, previsão visual separada, interpolação remota, animação procedural de caminhada/repouso, modelo em primeira pessoa, recoil, recarga e eliminação. `CharacterAnimator.update(position: Vector3, yaw: float, delta: float)` já é testado em 20/60/144 FPS. Não importar controller TPS, converter para terceira pessoa ou substituir animações sem caso de aceitação.

**Arquivos:** modificar `client/arena_view.gd`, `client/character_animator.gd`, `client/character_rig.gd`, `client/menu_settings.gd`; criar `client/camera_effects.gd` e `tests/camera_effects_test.gd` se a separação reduzir responsabilidades. Ampliar `tests/character_animation_test.gd`, `tests/avatar_facing_test.gd`, `tests/vertical_aim_test.gd`, `tests/combat_feedback_test.gd`, `tests/spectator_reveal_client_test.gd`.

**Interfaces:** preservar `ArenaView.camera_origin() -> Vector3`, `camera_direction() -> Vector3`, `apply_snapshot(states: Array, tick: int = -1) -> void`, `set_player_alive(peer_id: int, alive: bool) -> void` e `set_spectator_target(peer_id: int, spectator_active: bool = true) -> void`. Proposta `CameraEffects.sample(speed: float, delta: float) -> Transform3D`: retorna offset exclusivamente visual; configuração zero retorna identidade, sem ler papéis ou modificar `PlayerPrediction.state`. A mira de gameplay continua a de `MovementRules.aim_direction`.

- [ ] Acrescentar `test_zero_effects_identity`, `test_effects_never_write_official_aim`, `test_wall_clearance`, `test_dead_player_cannot_animate_alive`, `test_same_duration_20_60_144fps`; exigir câmera livre de penetração, erro de mira oficial zero e offsets limitados/configuráveis.
- [ ] Introduzir bob/sway moderados e opcionais em transform filho; reutilizar recoil/recarga existentes. ADS somente após confirmar arma compatível e aprovar FOV/tempo; não alterar acurácia silenciosamente.
- [ ] Preservar estados efetivos vivo/eliminado; `DOWNED` não existe e não é criado por uma animação. Aterrissagem usa estado vertical aprovado no SPEC 01; se não aprovado, registrar explicitamente como bloqueado.
- [ ] Rodar novas/existentes suítes e sessão visual com câmera/avatares/tiro nas taxas definidas, anexar capturas e erro de mira. Headless prova transforms, não qualidade visual final; commit e PR com limitações.

## SPEC 06 — benchmark gráfico antes do polimento

**Já existe:** mansão procedural, materiais Godot, iluminação, efeitos e geometria oficial separada da decoração. Renderer Compatibility é compromisso Web/desktop; recursos exclusivos de Forward+ não são automaticamente compatíveis.

**Arquivos:** criar `tests/scenes/graphics_benchmark.tscn`, `tests/graphics_benchmark.gd`, `tests/graphics_profiles_test.gd`, `client/graphics_profile.gd`, `docs/gameplay-research/06-benchmark.md`; alterar `client/mansion_art.gd`, `client/combat_fx.gd`, `client/arena_view.gd`, `client/menu_settings.gd` somente após baseline. Não alterar `shared/mansion_map.gd`/`arena_rules.gd` para decorar.

**Interfaces:** proposta `GraphicsProfile.apply_to(view: Node3D) -> void` afeta apenas nós visuais; perfis `low`, `baseline`, `high` com baseline equivalente à configuração existente. Benchmark registra versão, renderer, GPU/driver, resolução, FPS/frame time p50/p95/p99, CPU e contagem de efeitos/nós; GPU indisponível = métrica não medida, nunca zero.

- [ ] Criar benchmark de uma sala pequena com luzes, obstáculos e sequência de efeitos reproduzível; medir baseline antes de modificar materiais/iluminação. Aprovar orçamento p95 por plataforma com a medição real antes de declarar ganho aceitável.
- [ ] Acrescentar `test_profiles_keep_collision_contract`, `test_profile_preserves_target_visibility`, `test_effect_count_bounded`, `test_two_instances_same_world_state`; efeito/objeto decorativo não pode alterar colisão ou hitbox.
- [ ] Aplicar PBR, sombras/ambiente e pós-processamento apenas suportados por Godot 4.4.1 Compatibility; medir cada opção. Sem engine Wicked, plugins nativos ou assets não auditados.
- [ ] Objetos físicos que alterem gameplay exigem decisão separada de autoridade/DTO/replay; não adicionar `RigidBody3D` independente em cada cliente. No laboratório pode-se demonstrar física Godot visual sem afirmar que está integrada à simulação autoritativa atual.
- [ ] Rodar `tests/graphics_profiles_test.gd`, `tests/arena_layout_test.gd`, `tests/mansion_art_test.gd`, campanhas e benchmark gráfico em duas instâncias com diferentes FPS. Anexar frame times antes/depois, legibilidade e perfis; commit e PR. Sem hardware adequado, manter aceitação visual/desempenho pendente.

## SPEC 07 — robustez e instrumentação da rede existente

**Já existe:** transporte WebSocket encapsulado, handshake, limites, validação de origem, fila/época/ACK, salas isoladas, shutdown e adversariais. SPEC 02 possui a previsão; não duplicá-la aqui. TCP entrega ordenado/confiável mesmo quando o RPC declara modo transitório.

**Arquivos:** `server/websocket_server_transport.gd`, `client/websocket_client_transport.gd`, `server/authoritative_world.gd`, `shared/network_app.gd`, `shared/net_sync.gd`, `client/net_stats.gd`; ampliar `tests/round_adversarial_test.sh`, `tests/rooms_adversarial_test.sh`, `tests/rooms_resilience_test.sh`, `tests/adverse_cases_test.sh` e `tests/netcode_test.gd`; criar `docs/gameplay-research/07-network-delta.md`.

**Interfaces:** manter `AuthoritativeWorld.receive_commands(peer_id: int, payload: Variant, now_msec: int) -> Dictionary`, `step(gate: Callable, run_action: Callable, reject: Callable) -> void`, `ack_for(peer_id: int) -> Dictionary` e contratos RPC inventariados em [architecture-contracts.md](architecture-contracts.md). Nenhum papel/inventário adicional em snapshot; vida continua no modelo efetivo, sem inventar enum `DOWNED`/`LEFT`.

- [ ] Comparar conceitos de ioquake3 com as fronteiras existentes em texto independente, citando commit/arquivos do registro de licenças. Medir bytes/s, snapshots/s por peer, filas, idade dos comandos e latência/jitter para 4 e 8 clientes.
- [ ] Acrescentar `test_queue_flood_bounded`, `test_cross_room_old_epoch_rejected`, `test_duplicate_action_after_reset_rejected`, `test_shutdown_blocks_new_gameplay`; afirmar limites atuais 8 comandos/pacote, 32/fila, avanço de sequência ≤64, budget ≤12 ticks e ausência de dados de outra sala.
- [ ] Corrigir apenas limites/telemetria/validações demonstrados como ausentes; separar confiabilidade de eventos e estados sem prometer canais paralelos independentes sobre TCP. Se otimizar payload, registrar versão, schema e todos os produtores/consumidores antes da mudança.
- [ ] Rodar smoke, round, combate, sync, adversariais, resiliência, menu, campanhas 8 clientes/3 rodadas, encerramento e mutações. Repetir perfis aprovados do SPEC 02 e comparar métricas; commit e PR.
- [ ] Qualquer proposta ENet fica em documento/PR de decisão independente, com benchmark, hospedagem UDP e migração/rollback; não alterar transporte nesta etapa por conveniência.

## SPEC 08 — integração e certificação

**Pré-condições:** SPECs anteriores aprovados, decisões de movimento vertical/armas de papéis resolvidas, licenças verificadas e nenhuma regressão crítica aberta. Critérios da Master SPEC de detetive/assassino são bloqueadores se a regra correspondente continuar ausente; não substituir por combate da pistola comum e chamar de certificação completa.

**Arquivos:** criar `tests/scenes/gameplay_integration.tscn`, `tests/gameplay_integration_test.sh`, `tests/gameplay_integration_coordinator.gd`, `docs/gameplay-research/08-certification.md`; reutilizar `tests/campaign_coordinator.gd`/`campaign_test.sh`, `tests/combat_network_coordinator.gd` e suites de salas. Atualizar `architecture-contracts.md`, `test-matrix.md`, `license-register.md` com os contratos realmente aprovados; não substituir mapas de produção.

**Interfaces:** cena/coordenador usam as mesmas intenções e RPCs da produção, exclusivamente por flags de teste do editor; não habilitar controle de teste no servidor dedicado release. Receber `round_id`, época, resultado público e estado privado de cada cliente sem agregar segredos em DTO público.

- [ ] Criar casos de integração para lobby→PRONTO→rodada→movimento simultâneo→coleta/recarga→tiros válidos/inválidos→eliminação→resultado→reset; exigir mesmos peers, snapshot coerente e recursos restaurados.
- [ ] Executar quatro clientes no mínimo, oito na campanha e três rodadas; incluir detetive×assassino, detetive×inocente, arma especial do assassino somente com tabela aprovada, simultaneidade e desconexão nos momentos de reset. Os casos de papel novos devem falhar antes de suas implementações, não ser omitidos.
- [ ] Medir snapshots efetivos, ACK/erro de posição, correções, jitter, latência e frame times com perfis reproduzíveis; comparar baseline SPEC 00/02/06 com resultados integrados e budgets aprovados, registrando diferenças de hardware.
- [ ] Rodar todos os checks da matriz, teste Web local, export Linux dedicado/Windows e visual quando houver pré-requisitos; distinguir falha de ambiente de defeito do projeto. Publicação não é teste e continua desautorizada.
- [ ] Remover duplicações/interfaces somente com chamadas e cobertura demonstradas; revisar atribuições e licenças por arquivo, atualizar contratos e emitir relatório final com versões, commits, resultados, evidências, riscos e pendências. Commit e PR para revisão humana; sem merge automático.

## Critério de avanço entre SPECs

Uma branch nova parte da base explicitamente aprovada. Falha crítica, conflito de autoridade/protocolo, licença não verificada, critério de aceitação pendente ou falta de evidência interrompe a integração. O relatório pode propor adiamento/alteração de escopo, mas não contar o item como concluído sem decisão humana registrada. Aprovação técnica do agente não substitui aprovação de merge/deploy. Não iniciar o SPEC seguinte enquanto o anterior estiver aguardando a aprovação exigida.
