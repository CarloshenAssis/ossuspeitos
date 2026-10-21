# SPEC 00 — relatório dos testes iniciais

Data: 2026-10-21. Baseline de código: `dd15ff2ab29d5e67fccedc41c431c30eb7e32c6d`.

## Ambiente e método

Godot `4.4.1.stable.official.49a5bc7b6` (mesma versão do CI), Linux x86_64, execução headless. Sem alteração de fontes, testes ou workflows. Cada harness iniciou e encerrou seus próprios processos; as variantes foram executadas sequencialmente com portas locais distintas.

Preparação e comandos reproduzíveis:

```bash
cd /workspace/ossuspeitos
export GODOT_BIN=/workspace/.ossuspeitos-tools/Godot_v4.4.1-stable_linux.x86_64
export GAME_BIN="$GODOT_BIN" GAME_PATH="$PWD"
export XDG_CONFIG_HOME=/workspace/.ossuspeitos-state/config
export XDG_CACHE_HOME=/workspace/.ossuspeitos-state/cache
export XDG_DATA_HOME=/workspace/.ossuspeitos-state/data
"$GODOT_BIN" --headless --path . --editor --quit
for test in tests/*_test.gd; do
  timeout 90 "$GODOT_BIN" --headless --path . --script "$test"
done
# Os harnesses abaixo: TEST_LOG_DIR=<diretório exclusivo> TEST_PORT=<porta livre> bash tests/<nome>_test.sh
```

Importação: saída 0; log sem `SCRIPT ERROR`, `Parse Error` ou `ERROR:`. Para os scripts, aprovação exige saída 0 e marcador final esperado, além de ausência de erro de script/parse. Diagnósticos do motor são registrados separadamente abaixo; não foram suprimidos. Timeout externo: 90 s por script e 240 s por harness, além dos watchdogs próprios.

## Scripts GDScript

30/30 scripts concluíram com saída 0 e marcador de sucesso. Os contadores declarados somam 55.123 verificações; `movement_rules_test.gd` não publica contador. Essa soma não equivale a casos de teste independentes nem inclui as asserções dos harnesses.

| Script em `tests/` | Saída | Marcador / contagem | Tempo (s) |
| --- | --- | --- | --- |
| `arena_layout_test.gd` | 0 | `ARENA_LAYOUT_TEST_OK checks=5117 blockers=182 spawns=8 pickups=20 rooms=9` | 5.14 |
| `arena_visuals_test.gd` | 0 | `ARENA_VISUALS_TEST_OK checks=151` | 1.17 |
| `avatar_facing_test.gd` | 0 | `AVATAR_FACING_TEST_OK checks=27` | 1.12 |
| `character_animation_test.gd` | 0 | `CHARACTER_ANIMATION_TEST_OK checks=472` | 1.17 |
| `character_appearance_test.gd` | 0 | `CHARACTER_APPEARANCE_TEST_OK checks=142` | 1.17 |
| `combat_authority_test.gd` | 0 | `COMBAT_AUTHORITY_TEST_OK checks=60` | 1.12 |
| `combat_feedback_test.gd` | 0 | `COMBAT_FEEDBACK_TEST_OK checks=84` | 1.12 |
| `combat_network_coordinator_test.gd` | 0 | `COMBAT_NETWORK_COORDINATOR_TEST_OK checks=23` | 1.12 |
| `combat_rules_test.gd` | 0 | `COMBAT_RULES_TEST_OK checks=25` | 1.17 |
| `dedicated_config_test.gd` | 0 | `DEDICATED_CONFIG_TEST_OK checks=49` | 1.17 |
| `desktop_session_test.gd` | 0 | `DESKTOP_SESSION_TEST_OK checks=245` | 1.12 |
| `hud_presentation_test.gd` | 0 | `HUD_PRESENTATION_TEST_OK checks=19 layout=skipped` | 1.17 |
| `inventory_authority_test.gd` | 0 | `INVENTORY_AUTHORITY_TEST_OK checks=23` | 1.12 |
| `mansion_art_test.gd` | 0 | `MANSION_ART_TEST_OK checks=44135 items=1653 meshes=248 lights=24 materials=40` | 1.12 |
| `match_hud_test.gd` | 0 | `MATCH_HUD_TEST_OK checks=39` | 1.25 |
| `menu_test.gd` | 0 | `MENU_TEST_OK checks=194` | 1.3 |
| `movement_rules_test.gd` | 0 | `MOVEMENT_RULES_TEST_OK` | 1.12 |
| `netcode_test.gd` | 0 | `NETCODE_TEST_OK checks=143` | 1.12 |
| `player_messages_test.gd` | 0 | `PLAYER_MESSAGES_TEST_OK checks=676 messages=29` | 1.12 |
| `rooms_test.gd` | 0 | `ROOMS_TEST_OK checks=2626` | 1.17 |
| `round_authority_test.gd` | 0 | `ROUND_AUTHORITY_TEST_OK checks=192` | 1.17 |
| `round_hud_test.gd` | 0 | `ROUND_HUD_TEST_OK checks=98` | 1.12 |
| `round_reset_bodies_test.gd` | 0 | `ROUND_RESET_BODIES_TEST_OK checks=259` | 1.12 |
| `round_rules_test.gd` | 0 | `ROUND_RULES_TEST_OK checks=63` | 1.12 |
| `shutdown_handshake_test.gd` | 0 | `SHUTDOWN_HANDSHAKE_TEST_OK checks=47` | 1.17 |
| `spectator_reveal_authority_test.gd` | 0 | `SPECTATOR_REVEAL_AUTHORITY_TEST_OK checks=60` | 1.12 |
| `spectator_reveal_client_test.gd` | 0 | `SPECTATOR_REVEAL_CLIENT_TEST_OK checks=16` | 1.12 |
| `transition_metrics_test.gd` | 0 | `TRANSITION_METRICS_TEST_OK checks=30` | 1.17 |
| `vertical_aim_test.gd` | 0 | `VERTICAL_AIM_TEST_OK checks=81` | 1.12 |
| `weapon_rules_test.gd` | 0 | `WEAPON_RULES_TEST_OK checks=27` | 1.22 |

## Integração multiprocesso

19/19 variantes planejadas executadas; 19 aprovadas por saída e marcador. Nenhuma variante foi descartada para obter sucesso.

| Harness em `tests/` / variante | Parâmetros adicionais | Resultado | Evidência final | Tempo (s) |
| --- | --- | --- | --- | --- |
| `network_smoke_test.sh` / network_smoke | `padrão` | PASS (saída 0) | `SERVER_MOVEMENT_TEST_OK players=4 max_speed=3.300 rejected_impossible=1 ; SERVER_TEST_OK clients=4` | 2.28 |
| `combat_network_test.sh` / combat_network | `padrão` | PASS (saída 0) | `COMBAT_SERVER_TEST_OK clients=4 ; SERVER_TEST_OK clients=4 ; COMBAT_NETWORK_TEST_OK server=1 clients=4 extended=false` | 5.29 |
| `combat_network_test.sh` / combat_network8 | `COMBAT_CLIENTS=8 COMBAT_EXTENDED=true` | PASS (saída 0) | `COMBAT_SERVER_TEST_OK clients=8 ; SERVER_TEST_OK clients=8 ; COMBAT_NETWORK_TEST_OK server=1 clients=8 extended=true` | 27.32 |
| `round_network_test.sh` / round_network | `padrão` | PASS (saída 0) | `ROUND_NETWORK_OK server=1 clients=5 participants=4 late=1` | 4.33 |
| `round_adversarial_test.sh` / round_adversarial | `padrão` | PASS (saída 0) | `ROUND_ADVERSARIAL_OK server=1 participants=4 hostile=1` | 4.33 |
| `spectator_reveal_network_test.sh` / spectator_reveal_network | `padrão` | PASS (saída 0) | `SERVER_TEST_OK clients=4 ; SPECTATOR_REVEAL_NETWORK_TEST_OK clients=4` | 3.88 |
| `desktop_local_match_test.sh` / desktop_local_match | `padrão` | PASS (saída 0) | `DESKTOP_LOCAL_MATCH_TEST_OK clients=4 hosted_pid=9079` | 19.22 |
| `menu_flow_test.sh` / menu_flow | `padrão` | PASS (saída 0) | `MENU_FLOW_TEST_OK scenes=10` | 58.39 |
| `sync_network_test.sh` / sync_network_local | `PROFILE=local SEED=1 STALL=false` | PASS (saída 0) | `SYNC_NETWORK_TEST_OK profile=local seed=1 stall=false` | 18.18 |
| `sync_network_test.sh` / sync_network_rtt80 | `PROFILE=rtt80 SEED=1 STALL=false` | PASS (saída 0) | `SYNC_NETWORK_TEST_OK profile=rtt80 seed=1 stall=false` | 19.22 |
| `sync_network_test.sh` / sync_network_rtt150j | `PROFILE=rtt150j SEED=3 STALL=false` | PASS (saída 0) | `SYNC_NETWORK_TEST_OK profile=rtt150j seed=3 stall=false` | 20.22 |
| `sync_network_test.sh` / sync_network_stall | `PROFILE=rtt150j SEED=5 STALL=true` | PASS (saída 0) | `SYNC_NETWORK_TEST_OK profile=rtt150j seed=5 stall=true` | 20.22 |
| `campaign_test.sh` / campaign_local | `PROFILE=local SEED=1` | PASS (saída 0) | `CAMPAIGN_TEST_OK profile=local seed=1 clients=8 rounds=3 run=campaign-local-s1-dd15ff2-11188` | 82.19 |
| `campaign_test.sh` / campaign_rtt150j | `PROFILE=rtt150j SEED=4` | PASS (saída 0) | `CAMPAIGN_TEST_OK profile=rtt150j seed=4 clients=8 rounds=3 run=campaign-rtt150j-s4-dd15ff2-12096` | 90.56 |
| `adverse_cases_test.sh` / adverse_cases | `SEED=1` | PASS (saída 0) | `ADVERSE_CASES_TEST_OK cases=13 seed=1 run=adverse-s1-dd15ff2-12919` | 161.55 |
| `rooms_network_test.sh` / rooms_network | `padrão` | PASS (saída 0) | `ROOMS_NETWORK_TEST_OK` | 25.61 |
| `rooms_adversarial_test.sh` / rooms_adversarial | `padrão` | PASS (saída 0) | `ROOMS_ADVERSARIAL_TEST_OK` | 8.94 |
| `rooms_resilience_test.sh` / rooms_resilience | `padrão` | PASS (saída 0) | `ROOMS_RESILIENCE_TEST_OK` | 25.76 |
| `phase10_mutation_test.sh` / phase10_mutation | `padrão` | PASS (saída 0) | `PHASE10_MUTATION_TEST_OK caught=4` | 77.01 |

O sucesso de `phase10_mutation_test.sh` significa que quatro falhas deliberadas foram detectadas (`caught=4`); os subtestes dessas mutações devem falhar pelas razões esperadas. Não são regressões ignoradas nem testes desativados.

## Amostras de métricas de sincronização

Amostra: último marcador `NET_STATS ... stage=DUPLICATE` publicado pelo harness em cada perfil. São amostras de um cliente por execução, não agregados universais. RTT nominal não é tempo de ação observado; n=0 não fornece medição.

| Perfil | Cliente | Snapshot p95 / máximo (ms) | Erro de ACK máximo (m) | Ação → resultado p95 (ms) | Maior fila pendente |
| --- | --- | --- | --- | --- | --- |
| sync_network_local | client-3 | 55.2 / 55.6 | 0.0 | 34.8 | 5 |
| sync_network_rtt80 | client-3 | 55.3 / 55.7 | 0.0 | 124.2 | 11 |
| sync_network_rtt150j | client-3 | 68.9 / 75.8 | 0.0 | 214.3 | 16 |
| sync_network_stall | client-1 | 69.0 / 358.8 | 0.0 | 220.8 | 33 |

## Diagnósticos e limites do baseline

- `combat_feedback_test.gd`: marcador de sucesso e 84 checks, mas quatro mensagens `ERROR: Node not inside tree. Use look_at_from_position() instead.` e aviso de instâncias ObjectDB não liberadas. Em `client/arena_view.gd:567`, `tracer.look_at(...)` é chamado antes de `add_child(tracer)`, explicando o uso fora da árvore. É ordem de ciclo de vida no helper de produção, não falha de asserção nem erro de setup; correção fica para tarefa própria.
- `netcode_test.gd`: 143 checks e métricas de determinismo aprovados, mas aviso de ObjectDB não liberado e `ERROR: 9 resources still in use at exit`. Rerun diagnóstico com `--verbose` também termina com saída 0 e enumera RefCounted/RandomNumberGenerator retidos e nove GDScripts. A fixture `_combat()` em `tests/netcode_test.gd:411` armazena em `loop.action_runner` uma closure que captura o próprio `loop` e `combat`, suspeita concreta de ciclo de referência; não houve prova por alteração nem correção nesta tarefa. Não declarar a suíte livre de diagnósticos.
- Avisos recorrentes de `owner` inconsistente ao adicionar partes a `HeadPivot` aparecem em suites de arena/avatar/animação/feedback/reset/mira. São preexistentes neste baseline.
- Após a execução, nenhum processo Godot rastreado pelo executor permaneceu ativo. Restaram 12 entradas zumbi de `sleep` dos watchdogs, já encerradas e adotadas por PID 1; não são servidores vivos e não podem ser reaproveitadas. Isso limita uma alegação de limpeza integral da tabela de processos, sem invalidar as asserções funcionais dos harnesses.
- `hud_presentation_test.gd`: 19 checks passam, mas o próprio marcador informa `layout=skipped` em headless. Isso não valida layout visual/renderização.
- Perfis de atraso existentes: `local`, `rtt80` (40 ms em cada direção), `rtt150j` (65 ms em cada direção, jitter de 20 ms) e stall opcional de 400 ms. Os nomes não provam execução das latências exatas 50/100/200 ms da SPEC 02. Não há mecanismo de perda de pacotes no `tests/net_delay_peer.gd` inspecionado. Em WebSocket/TCP, perdas/retransmissões reais precisam de metodologia explícita; não confundir com descarte artificial de snapshots.

## Não executado nesta máquina

- Exportação Web + `web_playtest_test.sh`: Chromium existe, mas não há export Web pré-gerado nem templates Godot 4.4.1 instalados no diretório de dados usado. O teste requer `build/web-playtest/index.html` e módulos Playwright.
- Exportação Windows e teste do binário Windows: templates/binário não preparados nesta validação Linux.
- Build/teste de container (`container_test.sh` e campanha contra imagem): Docker 28.4.0 está disponível, mas as imagens de projeto não foram construídas. O build baixa editor/templates, compila exports e é uma validação separada do workflow `Dedicated server container`.
- Android: não há export/SDK configurado nesta validação; a SPEC 00 não introduz Android.
- Validação visual interativa, benchmark GPU/CPU/frame time e sessões `*_visual_session.sh`: não executados; testes de nós headless não os substituem.
- `latency_probe.sh`/sonda de produção: não executados para não interagir com Railway ou sessões de jogadores. Nenhum deploy, publicação ou mudança de configuração de produção foi realizado.

Os workflows do PR podem executar builds/exportações em runners próprios; o resultado remoto deve ser lido separadamente. Não atribuir sucesso de CI remoto aos testes locais acima.

## Evidências e rastreabilidade

Logs brutos e resultados JSON da instância: `/workspace/.ossuspeitos-state/spec00-tests/` (`import.log`, `gd-results.json`, `network-results-reviewed.json`, logs por script e subdiretórios por harness). Esses arquivos locais não são anexos persistidos do GitHub; este relatório versiona comandos, saídas resumidas, duração e resultado. Os manifests sanitizados `evidence/gd-results.json` e `evidence/network-results.json` acompanham o PR; `evidence/network-metrics.json` preserva amostras de métricas com perfil/seed e origem, sem payloads de papéis. Logs integrais do CI pertencem ao run/commit correspondente.

Impressões SHA-256 dos logs superiores usados nesta auditoria:

| Log | SHA-256 |
| --- | --- |
| `adverse_cases.log` | `e808208b9148ffcd24138c59b348403b61bdaaab064dfd429cdc47a873d7640e` |
| `arena_layout_test.log` | `4ec990bc8105c4e4b15dee65837e053682b3315a6f9e218786d47ac2d33919fd` |
| `arena_visuals_test.log` | `d7d9d42495022f0627d06962e63cfb205c329f1c86f1361202f6392e01749788` |
| `avatar_facing_test.log` | `1d2b054ce6fd89a1fe296d897cff9b033b6d92c3d3024e51ddc0836c52a994a1` |
| `campaign_local.log` | `7dc90a4762191f6ab360ac6e5103be6f343c6c55aebd5ac90dca60b0b0aea13a` |
| `campaign_rtt150j.log` | `9fa42e6b657942ed6cb3122b31fd70cc8052bec667d1649778f8c7f986d62c28` |
| `character_animation_test.log` | `2bc5b9e3367df5d9a40d52eab09b680349cfe35ef1afec1f1a68fb44d0af7701` |
| `character_appearance_test.log` | `ae923c013bc9821285633802894108d8e1600e25ccce636b4acda19e017987eb` |
| `combat_authority_test.log` | `13e6be6eb10cd913486c2db56bb31fef8e2b9ddd0c2558a4ad45b0177697497c` |
| `combat_feedback_test.log` | `71859d7f0547108dedf47a2fb68d69d6f1b5acb3031c370dc338bd3e5a143f0a` |
| `combat_network.log` | `4237133c99c3e3061cfb25afa3cceb46e39376626bf2db2491b3a3f6730c0e33` |
| `combat_network8.log` | `8b7f176d19928ae759deea24bf39e1b1a3ed6329949fa45c547b9a93197a2021` |
| `combat_network_coordinator_test.log` | `d4f857964f2ae7ab00b256d5246523c69b5e5345cb7803db6311a22160d0349c` |
| `combat_rules_test.log` | `ea231d829ed79b6b8b5d1a3f51fdb91302d43a59f40c66849fe93d9f1a9273ee` |
| `dedicated_config_test.log` | `6294db170e706c31dce7d882b735504f807c85eb83d2ca8efc661ce1175a93ce` |
| `desktop_local_match.log` | `c309a5884134e68efe21698302138cf1145e5d9a203c90aec80d0a82ace3d82c` |
| `desktop_session_test.log` | `e14a39a91eafa06aefd1c024d56d5040f458ba436f17abc88b9d241068279567` |
| `hud_presentation_test.log` | `f8a76b81dba85ddc5aab94339bead8faef02bd99c18301581bb7c9a1eb47fecc` |
| `import.log` | `b9f33072d628fcc66317248b05d6d5f15bf5051e566be614d2eb5f6fdc9e2ee3` |
| `inventory_authority_test.log` | `347b55ed0e65e2c6cc1802afebd765dfbafe752bb0cffe0c751323f05c7c8a09` |
| `mansion_art_test.log` | `e63361ae3776f76d100f148f0277c356680067057d7498bc0124e8520cbeb305` |
| `match_hud_test.log` | `4df156c0b8989e203a8e080e11e74422c9611a23f04ccd1d1752497504e6d583` |
| `menu_flow.log` | `1bbdf922314a3c35147407b92b9e5b9684185a977e0f3f4ddd8b57107b0e98be` |
| `menu_test.log` | `da64ff1b1e45cd34d5b243be1049945149f3dd3b22b8e5ad7c31bcf7e29e17a6` |
| `movement_rules_test.log` | `c3a1fa9c492e0cbbda42daf605cf9c72af235ae606109990db08e464a107a8f3` |
| `netcode-verbose.log` | `edad2c04ea5ff04f617673152ff29666af653d0d6e19c8d280c1d0d0666a59ae` |
| `netcode_test.log` | `be78d6df6ba4f3f26984e587a1630ed1df1cf74e000b51c0e7525964579b5571` |
| `network_smoke.log` | `ba7cdc80d168f2bd53ef7e7b96599a78a200d1bc397212d0aaf6167f74b7ec2c` |
| `phase10_mutation.log` | `e62230069914f8f84b8b29fc4236d52061aebe6b9ba5c5e6d23be01049dd091b` |
| `player_messages_test.log` | `38e3cbd1fcc06d55f1be4c84bed39983e159ea2b4b0cea3c93e54edb738fa617` |
| `rooms_adversarial.log` | `99ee5417d92e634a69234adf4e66668677c67e349651841c931420899e5a658b` |
| `rooms_network.log` | `dbffb39138a383ca97ac36064adbf5851fdb9301a501e7b31299354b1d725eaa` |
| `rooms_resilience.log` | `c6726718e52af21442c0ed418fa29e85e305ff1984332a2c88ddee7fc3ba330b` |
| `rooms_test.log` | `b6189c8782f5058e3296cf6ce857fa25cb22e79fc2ae4a919bf9d750516fb355` |
| `round_adversarial.log` | `39038de3f2791adf214afd88f83a89c15200a93d1b0cb43d396757a6627e2198` |
| `round_authority_test.log` | `8f02a86962d9144514d5ec7d768c3027135f7a5a5beff2792cf940db499bd399` |
| `round_hud_test.log` | `4f3242b7b9fdd8e049aa7020d483f73eeddacd53959f321a4bbc525ca3e9681c` |
| `round_network.log` | `6bb484925d1d992a685030c0769cfd48034488fdad7c45b846e94470434f3126` |
| `round_reset_bodies_test.log` | `c94deda5c638351697942ba4885d8207f129787a37a908c6535380c9f7e943d8` |
| `round_rules_test.log` | `b5e98d9f72f83db2703bffb952f740ae436c9b7404d4353bdcffa76fb60b2be6` |
| `shutdown_handshake_test.log` | `8ed01054ad201438e92cd70113e2975b64c067b08443ba215696b3c34f6119ad` |
| `spectator_reveal_authority_test.log` | `b2688ca9c44466425396bf4b65b0d69b6f999e263f47701165a189cdb42dcdf3` |
| `spectator_reveal_client_test.log` | `dab824b79d54b16a0163c4300d97e88ca6d3fb09e5b37675af51d0a08a05d14e` |
| `spectator_reveal_network.log` | `ecaf6744a652935e0955cfe8a7f8537d3ddd7c8e3e8fb77ecafab2b90532963d` |
| `sync_network_local.log` | `fd9d5fae01bbcd381e9abace6b5265a14267ded77cfe03df4aeba2c8b2d17e60` |
| `sync_network_rtt150j.log` | `26a317b397b26cbde3c7df97fceea4b0b9851d4c0e8f2a5cd0726e9677bdd307` |
| `sync_network_rtt80.log` | `c43ae10d6a47b3adcf5464b716cec84777c96758683ac32a4976abd413c6786e` |
| `sync_network_stall.log` | `1c39f415ff231a8c2b58f27d4d28e52fa1c1dac3f408d1ad8d2a07fc042bf2be` |
| `transition_metrics_test.log` | `6f47643afe19118465cb8e9f86a7829f62179826b38de8ce24474555fc7d3b7c` |
| `vertical_aim_test.log` | `46552e6eba6a0532bc0358e6f2ab58c2b1d1d06cdd8506283bf89435ea6a0abc` |
| `weapon_rules_test.log` | `a8063875ca50ecbaed64d9c55b54f301c2b18076d59a2e01194c36e0e5b72c5d` |
