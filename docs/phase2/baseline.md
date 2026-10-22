# Baseline independente — Fase 2

## Origem e ambiente

Fonte congelada: `59926cb74c6861c207ad16f7ad2793ea55bc9995` (HEAD validado do PR #31), extraída com `git archive` para `/workspace/phase2-baseline`, sem `.godot` inicial e sem editar o checkout de desenvolvimento. Os PRs anteriores não foram presumidos integrados à main. Foi lido o relatório final 01–08 e a investigação anterior de importação limpa.

Godot **4.4.1.stable.official.49a5bc7b6**, binário explícito de `/workspace/.ossuspeitos-tools`; não foi usado o `godot` 4.6 do PATH. Logs, runners reproduzíveis, resultados JSON e metadata estão em `/workspace/.ossuspeitos-state/phase2/baseline/`. A importação gráfica completa saiu **0**, sem `SCRIPT ERROR`, `Parse Error` ou `ERROR:`. Aviso conhecido de VSync não suportado no display software.

```sh
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
# Execute após extrair git archive 59926cb em /workspace/phase2-baseline:
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 \
VK_DRIVER_FILES=/workspace/.ossuspeitos-tools/vulkan/root/usr/share/vulkan/icd.d/lvp_icd.json \
LD_LIBRARY_PATH=/workspace/.ossuspeitos-tools/vulkan/root/usr/lib/x86_64-linux-gnu \
"$GODOT_BIN" --path /workspace/phase2-baseline --display-driver x11 \
  --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 --import
python3 /workspace/.ossuspeitos-state/phase2/baseline/gd-runner.py
python3 /workspace/.ossuspeitos-state/phase2/baseline/network-runner.py
```

O runner GDScript executa cada `tests/*_test.gd` que estende SceneTree com `--headless --path /workspace/phase2-baseline --script tests/<nome>`, limite 90 s, exigindo exit 0, marcador final e ausência de erros. O runner de rede fornece `GODOT_BIN`, `GAME_BIN`, `GAME_PATH`, `TEST_LOG_DIR` separado e portas 41000/41010/41020/41030/41040, limite 600 s por harness, exigindo marcador/exit correto e ausência de erros de script. Os harnesses foram executados em grupos próprios de processos com cleanup final. Nenhum Godot vivo pertencente ao arquivo baseline restou ao encerrar; oito zombies antigos, anteriores à missão e filhos do PID 1, foram identificados e não tocados. O display :99 preexistente foi preservado.

## Resultados reais

**37/37 suítes GDScript PASS** e **5/5 harnesses multiprocesso PASS**. Zero erros de engine/script/parse nessas execuções. Isto é uma nova baseline selecionada de rede, não a repetição dos 22 cenários completos do relatório 01–08. A cena integrada foi executada na suíte e novamente pelo wrapper com servidor e quatro clientes: **96 verificações PASS**.

| Suíte GDScript | Resultado | Duração observada (s) |
| --- | --- | ---: |
| `arena_layout_test.gd` | PASS | 5.13 |
| `arena_visuals_test.gd` | PASS | 1.17 |
| `avatar_facing_test.gd` | PASS | 1.17 |
| `camera_effects_test.gd` | PASS | 2.22 |
| `character_animation_test.gd` | PASS | 1.19 |
| `character_appearance_test.gd` | PASS | 1.17 |
| `combat_authority_test.gd` | PASS | 1.17 |
| `combat_feedback_test.gd` | PASS | 1.22 |
| `combat_network_coordinator_test.gd` | PASS | 1.17 |
| `combat_rules_test.gd` | PASS | 1.13 |
| `dedicated_config_test.gd` | PASS | 1.17 |
| `desktop_session_test.gd` | PASS | 1.12 |
| `gameplay_integration_test.gd` | PASS | 1.12 |
| `graphics_profiles_test.gd` | PASS | 1.28 |
| `gunplay_test.gd` | PASS | 1.23 |
| `hud_presentation_test.gd` | PASS | 1.12 |
| `inventory_authority_test.gd` | PASS | 1.12 |
| `mansion_art_test.gd` | PASS | 1.22 |
| `match_hud_test.gd` | PASS | 1.12 |
| `menu_test.gd` | PASS | 1.17 |
| `movement_config_test.gd` | PASS | 1.17 |
| `movement_rules_test.gd` | PASS | 1.17 |
| `netcode_test.gd` | PASS | 1.17 |
| `network_telemetry_test.gd` | PASS | 1.17 |
| `player_messages_test.gd` | PASS | 1.17 |
| `rooms_test.gd` | PASS | 1.22 |
| `round_authority_test.gd` | PASS | 1.17 |
| `round_hud_test.gd` | PASS | 1.17 |
| `round_reset_bodies_test.gd` | PASS | 1.22 |
| `round_rules_test.gd` | PASS | 1.17 |
| `shutdown_handshake_test.gd` | PASS | 1.17 |
| `spectator_reveal_authority_test.gd` | PASS | 1.17 |
| `spectator_reveal_client_test.gd` | PASS | 1.18 |
| `transition_metrics_test.gd` | PASS | 1.17 |
| `vertical_aim_test.gd` | PASS | 1.12 |
| `weapon_catalog_test.gd` | PASS | 1.12 |
| `weapon_rules_test.gd` | PASS | 1.12 |

| Harness | Parâmetros | Resultado | Duração observada (s) |
| --- | --- | --- | ---: |
| `network_smoke` | `{}` | PASS | 2.93 |
| `combat_network` | `{}` | PASS | 5.89 |
| `rooms_network` | `{}` | PASS | 26.47 |
| `sync_network_rtt200` | `{"PROFILE": "rtt200", "SEED": "1", "STALL": "false"}` | PASS | 20.23 |
| `gameplay_integration` | `{}` | PASS | 6.44 |

Os mesmos três avisos ObjectDB do baseline anterior ocorreram em `arena_visuals_test`, `avatar_facing_test` e `combat_feedback_test`: áudio ainda em encerramento. Não foram ocultados nem considerados novos ou corrigidos. O gate de erros acima não trata esses avisos conhecidos como ERROR.

## Medidas comparáveis e limites

Benchmark gráfico novo no arquivo baseline, após finalizar os testes próprios de rede/GDScript:

```sh
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 "$GODOT_BIN" --path /workspace/phase2-baseline \
  --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 \
  tests/scenes/graphics_benchmark.tscn -- --profile=baseline
```

Godot 4.4.1, Compatibility, **Mesa llvmpipe LLVM 19 software**, AMD EPYC 9V74, 960×540, 120 quadros de aquecimento e 300 medidos: **p50 13.531 ms / p95 20.979 ms / p99 24.466 ms / máximo 32.663 ms**; 248 meshes, 24 luzes e 294 filhos imediatos da view. `nodes=294` não é contagem recursiva do mapa. Execução única num host compartilhado: não certifica GPU física, FPS de hardware nem diferenças pequenas entre versões. O relatório anterior observava p95 24.429 ms no padrão; esta variação com o mesmo código reforça a necessidade de comparar na mesma sessão/carga, sem alegar ganho da Fase 2.

No sync RTT200, client-2 no estágio DUPLICATE observou 323 snapshots; intervalo p50 48.354 ms / p95 55.300 ms; fila pendente máxima 18, idade máxima 290 ms, erro de ACK posição/yaw/pitch máximo zero. Esses números são uma observação local de aplicação sobre TCP, não perda física, tráfego total nem média de todos os peers/estágios. O perfil injeta 100 ms em cada direção. Logs completos preservam os demais estágios.

Não medidos nesta rodada: CPU/memória comparativa detalhada, tempo de física isolado, bytes reais de fio, desempenho GPU física, Web/Windows/export/container, campanha 8×3 completa. Estes permanecem na matriz final da Fase 2, sem herdar aprovação dos resultados anteriores.
