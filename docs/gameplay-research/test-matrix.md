# Matriz de checks por SPEC

> A missão [autonomous-mission.md](autonomous-mission.md) substituiu as pausas de aprovação entre SPECs. A seção final registra os checks novos; os nove gates existentes e a proibição de merge/publicação permanecem.

Data: 2026-10-21. Base: `dd15ff2ab29d5e67fccedc41c431c30eb7e32c6d`.
Esta é uma proposta para revisão, não uma alteração de proteção ou CI.
Resultados desta execução: [initial-test-report.md](initial-test-report.md).
Fonte de requisitos: [master-spec-v1.md](master-spec-v1.md).

## Gates comuns

Todos os PRs de SPEC devem passar os **nove checks existentes**, sem filtros de
caminho que façam um check obrigatório desaparecer:

| Workflow | Nome exato do check/job a exigir |
| --- | --- |
| Godot network tests | `network-tests`, `netcode-tests`, `match-tests`, `menu-tests`, `rooms-tests` |
| Dedicated server container | `server-container` |
| Godot Web build (demo + playtest) | `build-web-demo` |
| Godot Windows playtest build | `export-windows`, `smoke-windows` |

São nove checks (5 + 1 + 1 + 2). Confirmar os nove nomes na primeira execução
deste PR antes de gravar uma regra. Selecionar a origem GitHub Actions; não aceitar
um status homônimo de outra integração. O job `deploy-pages` NÃO é um gate de PR.
`probe` tem filtro de caminhos e acessa produção; `web-probe` é manual. Não exigir
nenhum deles universalmente e não os executar nesta preparação.

Requisitos transversais: importação Godot 4.4.1 sem erro de parse/script, testes
realmente concluídos (marcador final + código de saída), sem vazamento de papéis,
regressões adversariais, reset de rodada e isolamento de salas. Checks locais
não substituem exports/containers no CI; checks CI pendentes não são aprovação.

## Matriz adicional por SPEC

Os casos **novos propostos** abaixo ainda não existem e não foram executados.
Eles serão incorporados aos jobs existentes no PR de cada SPEC, sem remover
asserções. Não configurar nomes de checks futuros como obrigatórios antes de
existirem.

| SPEC | Regressão existente mínima local | Novas evidências exigidas antes da revisão |
| --- | --- | --- |
| 00 | Importação; todos os `tests/*_test.gd`; suítes headless de rede, combate, salas e campanha conforme relatório | Auditoria, contratos, licenças verificadas em sete SHAs, plano 01–08; diff somente docs; push e PR confirmados |
| 01 | `movement_rules_test.gd`, `netcode_test.gd`, `arena_layout_test.gd`, `vertical_aim_test.gd`; `network_smoke_test.sh`, `sync_network_test.sh` | Eixos/diagonal, aceleração/parada, limite autoritativo e replay determinístico. Sprint, salto, gravidade/rampas só após decisão aprovada sobre o modelo planar e consumidores do protocolo |
| 02 | `netcode_test.gd`, `vertical_aim_test.gd`; `sync_network_test.sh` em todos os perfis CI e com stall | Antes/depois de erro previsto/oficial p50/p95/máximo, tempo de convergência, buffers, repetidos/obsoletos, jitter e perfis explícitos 0/50/100/200 ms. Não chamar atraso de aplicação de perda TCP real |
| 03 | `weapon_rules_test.gd`, `inventory_authority_test.gd`, `combat_rules_test.gd`, `combat_authority_test.gd`, `combat_network_coordinator_test.gd`; `combat_network_test.sh` 4 e 8 clientes | Arma inválida, munição zero, cooldown, morto, duplicata, obstrução, tiros simultâneos. Regras especiais por papel são lacuna: decisão explícita e testes antes de alterar o dano atual |
| 04 | Suites de combate acima + `vertical_aim_test.gd`, `combat_feedback_test.gd` | Spread por RNG do servidor reproduzível; alcance, obstáculo, recuperação e precisão em movimento; feedback não confirma dano e não aceita seed cliente |
| 05 | `avatar_facing_test.gd`, `character_animation_test.gd`, `character_appearance_test.gd`, `combat_feedback_test.gd`, `spectator_reveal_client_test.gd`, `match_hud_test.gd`; `spectator_reveal_network_test.sh` | Câmera/pitch nos limites, FPS variados, efeitos independentes da mira oficial, eliminado sem controle; teste gráfico e capturas. DOWNED não existe: não presumir implementação |
| 06 | `arena_layout_test.gd`, `arena_visuals_test.gd`, `mansion_art_test.gd`, `movement_rules_test.gd`; `build-web-demo` e servidor headless | Benchmark isolado antes/depois, hardware/renderer/resolução, p50/p95 frame time, CPU/GPU quando disponível, legibilidade; colisores visuais não substituem geometria analítica autoritativa |
| 07 | `netcode_test.gd`, `rooms_test.gd`, `shutdown_handshake_test.gd`; sync, round, rooms, adversariais, resilience e campanha | Filas e memória limitadas, mensagens inválidas, duplicadas/atrasadas, desconexão, shutdown; métricas de bytes/s e snapshots. Preservar WebSocket/TCP; proposta ENet separada |
| 08 | Todos os nove checks CI e toda matriz automatizada, inclusive mutações e campanha 8 clientes/3 rodadas | Cena integrada de teste separada, quatro clientes mínimo, regras realmente aprovadas, replay/reset, comparação baseline, revisão de licença e relatório final; funcionalidades especiais ausentes não podem ser certificadas como existentes |

## Comandos e perfis existentes

Preparação (Bash, dentro de `/workspace/ossuspeitos`):

```bash
export GODOT_BIN=/workspace/.ossuspeitos-tools/Godot_v4.4.1-stable_linux.x86_64
export XDG_CONFIG_HOME=/workspace/.ossuspeitos-state/config
export XDG_CACHE_HOME=/workspace/.ossuspeitos-state/cache
export XDG_DATA_HOME=/workspace/.ossuspeitos-state/data
"$GODOT_BIN" --headless --path . --editor --quit
"$GODOT_BIN" --headless --path . --script tests/netcode_test.gd
GODOT_BIN="$GODOT_BIN" ./tests/network_smoke_test.sh
GODOT_BIN="$GODOT_BIN" ./tests/combat_network_test.sh
COMBAT_CLIENTS=8 COMBAT_EXTENDED=true GODOT_BIN="$GODOT_BIN" ./tests/combat_network_test.sh
PROFILE=local SEED=1 GODOT_BIN="$GODOT_BIN" ./tests/sync_network_test.sh
PROFILE=rtt80 SEED=1 GODOT_BIN="$GODOT_BIN" ./tests/sync_network_test.sh
PROFILE=rtt150j SEED=3 GODOT_BIN="$GODOT_BIN" ./tests/sync_network_test.sh
PROFILE=rtt150j SEED=5 STALL=true GODOT_BIN="$GODOT_BIN" ./tests/sync_network_test.sh
PROFILE=local SEED=1 GODOT_BIN="$GODOT_BIN" ./tests/campaign_test.sh
PROFILE=rtt150j SEED=4 GODOT_BIN="$GODOT_BIN" ./tests/campaign_test.sh
```

Os perfis e seeds acima correspondem aos cenários de sincronização e campanha
em `.github/workflows/godot-network-tests.yml`; preservá-los nas regressões.
Guardar `TEST_LOG_DIR` fora do checkout, o status original, duração, versão, SHA,
perfil e seed. Verificar marcadores finais específicos de cada harness.
Suítes adversariais/mutações contêm recusas e falhas esperadas internas:
o status final do harness decide se o caso foi detectado corretamente.

## Gate para avançar

SPEC N: branch própria → testes + evidências → PR → revisão humana → merge
autorizado. SPEC N+1 só começa após aprovação do anterior e atualização da base.
Não habilitar auto-merge. Build de teste/artifact não equivale a autorização
para publicação no Pages/Railway. Não despachar sonda de produção como teste local.

## Matriz implementada na branch de integração

`gameplay-specs.yml` acrescenta o job independente **`gameplay-specs`** (20 minutos), sem alterar os cinco workflows existentes. Ele importa o projeto no Godot 4.4.1, exige marcadores e rejeita erros de script/parse nas novas suítes de movimento, catálogo, gunplay, câmera, perfis gráficos e telemetria. Também executa a regressão de lifecycle do wrapper, a integração obrigatória servidor+4 e sync rtt50/rtt100/rtt200. Logs são retidos mesmo em falha. Não possui permissão de publicação.

O décimo check só deve ser tornado obrigatório após sua primeira execução verde e conferência do nome/origem no PR. Proposta de proteção: os nove gates originais + `gameplay-specs`, PR obrigatório, branch atualizada, conversas resolvidas e sem force-push/exclusão. Nenhuma regra foi gravada pela API nesta missão.

Os novos arquivos não substituem os testes antigos. A regressão global inclui todos os `tests/*_test.gd`, os 19 cenários multiprocesso originais, os três perfis adicionais, a integração e sua regressão de encerramento. Resultados efetivos ficam no relatório final; marcador sem exit correto não é aprovação.
