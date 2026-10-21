# SPEC 01 — configuração compatível de movimento

Implementado em 2026-10-21 sobre `ac4f0ed`, na branch `codex/gameplay-specs-01-08`, após o gate do PR #30 informado como concluído. Esta entrega implementa a parametrização compatível do movimento FPS existente. A extensão vertical fica explicitamente adiada pela decisão abaixo; não é uma capacidade implementada.

## Implementação e API

`shared/movement_config.gd` define `MovementConfig extends Resource`, com campos exportados `walk_speed=5.0` m/s, `ground_acceleration=18.0` m/s² e `ground_deceleration=18.0` m/s². O único recurso ativo é `shared/default_movement_config.tres`, incluído no build. `validate() -> String` retorna vazio se válido, ou `movement_config_<campo>` se inválido. Todos os valores precisam ser finitos e estritamente positivos; velocidade tem teto inclusivo de 5 e aceleração/desaceleração, de 60. As faixas do Inspector não substituem a validação de runtime.

Ao inicializar `MovementRules`, o recurso é carregado sem reutilizar o cache mutável do ResourceLoader, validado e convertido por `validated_parameters()` em um Dictionary somente leitura com cópias escalares. O Resource não é retido como configuração ativa. Alterar um Resource carregado externamente não altera o movimento. Configuração empacotada inválida gera erro explícito de inicialização; `command_rejection`/`simulate_command` devolvem o motivo antes de aplicar mira, e `step_movement` registra a recusa sem alterar estado. Não há fallback silencioso.

Servidor (`AuthoritativeWorld`) e cliente (`PlayerPrediction`) continuam chamando as mesmas funções compartilhadas. `step_movement(state, move, delta)` e `simulate_command(state, move, dyaw, dpitch)` preservam assinaturas. As constantes `MAX_SPEED=5` e `ACCELERATION=18` permanecem para consumidores existentes. O integrador único usa desaceleração somente quando `move == Vector2.ZERO`; entrada não nula, inclusive inversão de direção, usa aceleração. Com defaults, a ordem das operações e os resultados antigos são preservados.

Para ajustar o jogo, editar o `.tres` empacotado, validar e distribuir o mesmo build a todos os peers. Não existe configuração por RPC, jogador, CLI, handshake ou override em runtime. Para ferramentas locais, `MovementRules.step_with_config(state, move, delta, config: Resource) -> String` valida uma configuração explícita e usa o mesmo integrador de produção; não instala nem modifica a configuração ativa. Exemplo: um Resource com aceleração 6 e desaceleração 30 produz incrementos de 0,1 m/s com entrada e redução de 0,5 m/s ao parar por tick de 1/60 s. Esta API não é RPC.

Colisão XZ, subpassos, deslizamento por eixo, Y=1, input, regras de mira, ações e protocolo 11 não mudam. Não se adicionam ações a `GameControls`, pois esta etapa não cria controles novos. Não há segundo controlador.

## Decisão e referência

Salto, gravidade, ar, sprint, rampas e grounded são adiados. Exigem design de regras, simulação vertical determinística e, se necessário, migração coordenada do protocolo; não decorrem desta parametrização. A missão autônoma permite registrar esse recorte sem nova pausa de aprovação. Ver também `docs/decisions.md`.

Referência conceitual: FirstPersonStarter, SHA `893db99a10eedadbd8189c040fb4d41fdf6ca46a`, MIT, conforme `license-register.md`. O registro descreve parâmetros separados de aceleração/desaceleração no controlador estudado. Esta implementação é original sobre o integrador existente; nenhum código ou asset da referência foi copiado e o controlador CharacterBody3D não foi incorporado.

## TDD e verificação

Godot homologado: `/workspace/.ossuspeitos-tools/Godot_v4.4.1-stable_linux.x86_64`, versão 4.4.1. Variáveis: `XDG_CONFIG_HOME=/workspace/.ossuspeitos-state/config`, `XDG_CACHE_HOME=/workspace/.ossuspeitos-state/cache`, `XDG_DATA_HOME=/workspace/.ossuspeitos-state/data`. Logs preservados fora do checkout em `/workspace/.ossuspeitos-state/mission-sdd/spec01/`.

O teste foi escrito antes da implementação. A primeira tentativa teve erro de parser por chamada dinâmica à classe; foi corrigida antes do ciclo red válido. O red válido executou a asserção `MovementConfig Resource must exist`, retornou 1 e não falhou apenas por parsing (`red.log`). Em seguida a implementação passou o teste real.

`tests/movement_config_test.gd` exige `MOVEMENT_CONFIG_TEST_OK` e saída 0 após asserções reais: defaults, valores golden por tick, diagonal com epsilon, parada monotônica em 17 ticks desde 5 m/s, ausência de drift, aceleração/desaceleração distintas, inversão usando aceleração, velocidade configurada, limites inclusivos, cada campo com NaN/±INF/zero/negativo/acima do teto, rejeição sem mutação de estado, Resource errado/nulo, snapshot imutável e isolamento de mutações externas. Checkpoints congelados da implementação de `ac4f0ed` cobrem partida, parada, reversão, diagonal com giro e mira, tokens e deslizamento na borda. O teste não contém cópia do integrador. Produção e replay são comparados a cada tick e aos checkpoints independentes do baseline.

| Verificação | Resultado observado |
| --- | --- |
| `--headless --path . --script tests/movement_config_test.gd` | 0, `MOVEMENT_CONFIG_TEST_OK` |
| `tests/movement_rules_test.gd` | 0, `MOVEMENT_RULES_TEST_OK` |
| `tests/netcode_test.gd` | 0, `NETCODE_TEST_OK checks=143`; erro máximo de ACK impresso 0,000000 m; convergência local/rtt80/rtt150j 0,100/0,133/0,200 s |
| `tests/arena_layout_test.gd` | 0, `ARENA_LAYOUT_TEST_OK checks=5117`, 182 blockers, 8 spawns |
| `tests/vertical_aim_test.gd` | 0, `VERTICAL_AIM_TEST_OK checks=81` (mira vertical existente, não movimento vertical) |
| `GODOT_BIN=... ./tests/network_smoke_test.sh` | 0, `NETWORK_SMOKE_OK server=1 clients=4`; servidor e quatro clientes saíram 0 |
| `PROFILE=local SEED=1 GODOT_BIN=... ./tests/sync_network_test.sh` | 0, `SYNC_NETWORK_TEST_OK profile=local seed=1 stall=false`; servidor e quatro clientes saíram 0 |
| Fixture isolada com `.tres` empacotado inválido (`walk_speed=0`) | 0, `INVALID_BUNDLE_REJECTED_BEFORE_SIMULATION_OK`; erros explícitos esperados de inicialização/movimento, nenhum estado/mira alterado |

A fixture copia o código real para um projeto isolado fora do checkout; não altera o recurso ativo do repositório. O teste de configuração foi repetido após ampliar as verificações, com saída 0. `git diff --check` passou.

No sync local: position/yaw/pitch/observer/ACK errors impressos 0,000000; overlaps=0, corrections_small/large=0, recoveries=0, privacy violations=0. O ator teve max_pending=5 e max_pending_age=70 ms; a janela de snapshots da etapa MOVE teve p50=48,3/p95=55,5/max=56,6 ms. São observações desta execução, não promessa de desempenho. O cliente incompatível saiu 1 como esperado, com `JOIN_REJECTED ... protocol_version`.

Limitações: testes headless e loopback, sem avaliação visual, Android/Web/export nem latência adicional multiprocesso neste SPEC. O netcode mantém os diagnósticos prévios de ObjectDB e 9 resources em uso ao sair; não foram ocultados nem corrigidos aqui. A impressão de métricas existente arredonda erros pequenos (melhoria reservada ao SPEC 02). A configuração não é negociada: builds divergentes continuam fora do contrato. Não se declara extensão vertical implementada ou suíte completa de CI executada localmente.
