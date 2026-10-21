# SPEC 00 — Auditoria e baseline do Suspeitos

Data: 2026-10-21. Commit auditado: `dd15ff2ab29d5e67fccedc41c431c30eb7e32c6d`. Escopo: documentação, auditoria e planejamento; nenhuma alteração de gameplay, transporte, testes, dependências ou configuração de produção.

## Método e fontes de verdade

Inspeção estrutural dos scripts em `client/`, `server/` e `shared/`, cenas, configuração Godot, export presets, scripts de deploy e workflows; leitura dos contratos efetivos de movimento, comandos, previsão, combate, rodadas, salas e apresentação. `docs/decisions.md`, `docs/netcode.md` e `docs/test-matrix.md` são histórico e apoio, não substituem código e execução. Testes executados nesta tarefa e limitações são registrados na [matriz](test-matrix.md) e relatório de evidências associado. Não inferir que o deploy remoto executa este SHA sem consultar o serviço; este SPEC não faz chamadas de gameplay à produção.

## Motor e ferramentas

- CI e Dockerfile fixam **Godot 4.4.1 stable**, edição não-.NET; binário esperado `4.4.1.stable.official.49a5bc7b6`. README aceita4.4+, mas compatibilidade com versões posteriores não foi certificada.
- `project.godot` não fixa feature tag/versão nem física; renderer é `gl_compatibility`, inclusive mobile. Tick padrão Godot60 Hz é combinado com `NetSync`60 Hz.
- Ambiente cloud também oferece Godot4.6.3 no PATH; para baseline usar explicitamente `/workspace/.ossuspeitos-tools/Godot_v4.4.1-stable_linux.x86_64`. O editor4.4.1 foi instalado com checksum SHA-512 do Dockerfile verificado, sem desabilitar TLS.
- Projeto GDScript, sem package manager, plugin nativo ou dependência de banco. Bash e Python3 suportam harnesses/relatórios. Templates, exportadores, Chromium, display/GPU e Docker são requisitos adicionais conforme cenário, não pré-requisitos das regras headless.
- Configuração/cache/dados graváveis nesta máquina ficam em `/workspace/.ossuspeitos-state/{config,cache,data}` via XDG_CONFIG_HOME/XDG_CACHE_HOME/XDG_DATA_HOME. Cache `.godot/`, `*.uid` e build são ignorados. Não versionar logs ou segredos por acidente.

## Mapa do repositório

| Caminho | Papel atual |
| --- | --- |
| `project.godot`, `shared/network_app.tscn`, `shared/network_app.gd` | Entrypoint, modos, composição, RPCs e eventos por sala. |
| `shared/movement_rules.gd`, `net_sync.gd`, `player_prediction.gd` | Simulação determinística, protocolo de comandos e previsão/replay. |
| `shared/mansion_map.gd`, `arena_rules.gd` | Mapa oficial, colisão analítica, spawns/pickups e raycast. |
| `shared/round_rules.gd`, `round_state.gd`, `role.gd`, `room_rules.gd` | Regras públicas determinísticas, fases, validações e DTOs. |
| `shared/weapon_definition.gd`, `weapon_rules.gd`, `body_rules.gd` | Definição/validação de arma e DTO público de corpos. |
| `shared/game_controls.gd`, `character_appearance.gd`, `transition_metrics.gd` | InputMap, aparência pública e instrumentação. |
| `server/authoritative_world.gd` | Estado/fila/orçamento de comandos e snapshots/ACK. |
| `server/combat_authority.gd`, `combat_rules.gd`, `inventory_authority.gd` | Armas, pickups, munição, tiro, dano e eventos oficiais. |
| `server/round_authority.gd`, `lobby_registry.gd`, `match_room.gd`, `room_registry.gd` | Estado secreto/vida, sessões e isolamento de salas. |
| `server/body_registry.gd`, `shutdown_handshake.gd`, `dedicated_config.gd` | Corpos, encerramento correlacionado e contrato de produção. |
| `client/websocket_client_transport.gd`, `server/websocket_server_transport.gd` | Adaptadores TCP/WebSocket. |
| `client/arena_view.gd`, `remote_interpolator.gd`, `character_rig.gd`, `character_animator.gd` | Câmera FPS, apresentação, animação procedural e interpolação. |
| `client/arena_models.gd`, `mansion_art.gd`, `combat_fx.gd`, `sfx_bank.gd`, `crosshair.gd` | Modelos/ambiente/feedback cosméticos. |
| `client/desktop_menu.gd`, `desktop_session.gd`, `menu_flow.gd`, `menu_settings.gd`, `online_endpoint.gd` | Menu, subprocesso de sala local, preferências e endpoint. |
| `client/menu_theme.gd`, `menu_backdrop.gd`, `menu_spinner.gd`, `hud_style.gd`, `round_hud.gd`, `player_messages.gd`, `net_stats.gd` | UI, mensagens e telemetria de cliente. |
| `client/visual_demo.gd` | Apresentação offline explicitamente isolada de autoridade/rede. |
| `assets/characters/` | Oito personagens GLB e import configs; procedência histórica em decisões. |
| `tests/` | Regras, cliente/UI, coordenadores, adversários, rede real multiprocesso, campanha, export e evidência visual. |
| `.github/workflows/` | Network, Web/Pages, Windows, container e probe online. |
| `Dockerfile`, `deploy/`, `railway.json`, `export_presets.cfg` | Build/export dedicado e start; nada executado em produção nesta tarefa. |
| `web/site/index.html` | Landing estática para demo/playtest Web. |
| `docs/`, `AGENTS.md`, `agents/`, skills locais | Decisões, operação e instruções de trabalho, não módulos de gameplay. |

## Estado real por sistema

| Sistema | Já implementado | Lacuna / próximo trabalho útil | Duplicação a evitar |
| --- | --- | --- | --- |
| Movimento (SPEC01) | WASD/diagonal validada, aceleração/frenagem, velocidade máxima5, mira vertical, colisão em planta determinística e limites. | Configuração modular; decidir salto/sprint/rampas, pois Y é fixo e esses comportamentos não existem. | Substituir por controlador offline CharacterBody sem simulação comum. |
| Predição (SPEC02) | Input sequenciado/epoch, previsão local, ACK/replay, correção visual, interpolação remota, limites/telemetria e atraso artificial. | Baseline específico0/50/100/200 ms; jitter/perda/reordenação distinguindo TCP de UDP e métricas antes/depois. | Segundo PredictionBuffer, reconciliador ou cronologia de ações. |
| Combate (SPEC03) | Catálogo validado, pistola comum, pickup/ammo/recarga, cooldown, hitscan bloqueado por volumes, dano e morte autoritativos, eventos sanitizados. | Configuração por arma e separação explícita de regras especiais ausentes. | Recriar inventário, pipeline de intenção, HitResolver paralelo ou importar engine C++. |
| Gunplay (SPEC04) | Alcance/cadência configurados, campo spread e RNG interno, recuo visual da arma. | Spread atual0; recoil lógico/precisão movimento/superfícies não integrados, fixtures reproduzíveis e calibração. | Confundir tiro visual previsto com dano aceito ou criar RNG escolhido por cliente. |
| Câmera/animação (SPEC05) | FPS com yaw/pitch, pivôs GLB procedurais, idle/walk, recoil/recarga, hit feedback, espectador autorizado. | Bob/sway/ADS/perfis e transições de novos estados apenas quando aprovados; medir taxas de quadro. | Importar AnimationTree/TPS completo ou dois escritores de transform. |
| Gráficos/física (SPEC06) | Mansão procedural, materiais, ambiente e luzes, efeitos leves, colisão analítica oficial compartilhada. | Benchmark gráfico real, perfis, sombras orçadas e autoridade de qualquer objeto móvel. | Runtime WickedEngine, troca implícita de renderer/física ou blockers visuais divergentes. |
| Rede (SPEC07) | Protocolo11, WebSocket/TCP, salas isoladas, filas limitadas, descarte, snapshots/ACK, shutdown e testes hostis. | Medir/conter payloads e filas adicionais se necessário; documentar proposta de transporte separada. | Reimplementar SPEC02 ou converter para ENet automaticamente. |
| Integração (SPEC08) | Campanha8 clientes/3 rodadas, resets, corpos, reveal, lobby ready, testes de erros e builds. | Certificar somente incrementos aprovados, revisar licença e métricas completas. | Substituir mapa/rodada ou declarar regras sociais ainda ausentes como aprovadas. |

Não há lojas/créditos, arma letal especial de assassino, punição de detetive por inocente, ressurreição33%, DOWNED, voz, contas/ranking ou matchmaking. Papéis e vitória existem; dano da pistola comum não diferencia papéis. A Master SPEC08 lista cenários de arma especial e penalidade: são lacunas de regra, não um contrato já implementado que se possa testar como pronto. Decidir escopo antes de incluí-las numa etapa; não implementadas no SPEC00.

## Contratos críticos

O inventário detalhado está em [architecture-contracts.md](architecture-contracts.md). Principais limites: protocolo11; cliente envia intenção, não resultado; identidade derivada da conexão; isolamento por `MatchRoom`; mapa de papéis só no servidor e revelado após ENDED; snapshot público e ACK privado separados; hitbox/colisão vindas da mesma geometria; simulação60 Hz e snapshot20 Hz; movimento Y fixo; vida boolean+health em vez de enum de incapacitação; câmera e efeitos cosméticos não decidem tiro.

## Evidências estáticas, inconsistências e riscos

1. `docs/netcode.md` começa pelo protocolo8 antes da implementação; ler seções posteriores e código atual antes de copiar formatos antigos. Protocolo11 não usa RPCs separadas de request_fire/reload/pickup na rede.
2. `README.md` ainda descreve arena graybox29×29 e4 armas; fonte atual é mansão com8 armas e12 munições. `ArenaRules.PICKUP_POSITIONS` conserva comentário antigo0..3/4..7. `docs/mansion-plan.md` conserva checkpoints de fase8 em PR; decisões posteriores já descrevem salas/protocolo11. Não usar esses textos como estado corrente.
3. Comentários antigos sobre ausência de animação GLB ou endpoint vazio não correspondem aos pivôs/animação procedurais atuais nem ao URL em `project.godot`. São dívida documental, não motivo para remover funcionalidade.
4. `CombatAuthority._apply_damage` envia causa `shot`, mas `RoundRules.ALLOWED_CAUSES` a sanitiza para `unknown`. Preservar neste PR e tratar eventual correção com teste específico posterior.
5. A geometria oficial é analítica e plana; importar salto/rampas afeta invariantes de colisão, replay, hitscan, mapa, snapshots e avatar. Alterar o protocolo exige atualizar consumidores e testes de recusa de versões.
6. Sem lag compensation. Atraso de aplicação sobre loopback não certifica rede pública nem perda/reordenação TCP real. GL Compatibility e execução headless não validam qualidade visual/GPU ou export Android.
7. `docs/decisions.md` registra GLBs gerados em outro repositório (`personagem_3d`) sem licença declarada. Arquivos locais não trazem licença individual. Não remover assets existentes neste SPEC; antes de redistribuição/incorporação adicional, obter evidência de autoria/permissão. [Registro de licenças](license-register.md) diferencia referências novas e assets existentes.
8. Não foi demonstrado código morto por análise de alcançabilidade completa. Demo offline, coordenadores, wrappers de export e helpers usados só em teste não devem ser classificados como mortos. Métodos legados de validação de tiro ainda são usados internamente e por testes, mesmo sem RPC de cliente correspondente.
9. Presets dedicados excluem testes na produção e incluem coordenação em preset de teste separado; flags/mutações não devem vazar para build de produção. Docker fixa imagens e checksum, não relaxar verificações para contornar instalação.

## Execução local de referência

```bash
cd /workspace/ossuspeitos
export GODOT_BIN=/workspace/.ossuspeitos-tools/Godot_v4.4.1-stable_linux.x86_64
export XDG_CONFIG_HOME=/workspace/.ossuspeitos-state/config
export XDG_CACHE_HOME=/workspace/.ossuspeitos-state/cache
export XDG_DATA_HOME=/workspace/.ossuspeitos-state/data
"$GODOT_BIN" --headless --path . --editor --quit
"$GODOT_BIN" --headless --path . -- --mode=server
# Em terminais distintos, variar client-id em pelo menos quatro clientes:
"$GODOT_BIN" --headless --path . -- --mode=client --client-id=client-1
# Preferir harness: inicia e encerra os próprios processos com asserções.
./tests/combat_network_test.sh
./tests/rooms_network_test.sh
```

Para salas: servidor `--mode=server --rooms=true`; dedicado exige `--mode=dedicated`, usa salas sempre e aceita somente argumentos de produção. Não iniciar servidor manual na mesma porta de um harness. Não fazer probe contra Railway sem autorização específica: mesmo uma sonda pode criar sessão/sala visível.

## Critério de aceite do SPEC00

- Mapa arquitetural e interfaces registrados; evidências de licença de sete referências mantidas no registro.
- Testes executados, falhas e checks não executados separados na matriz/relatório, sem alegar certificação de plataformas não testadas.
- Plano01–08 incremental apoiado nos módulos reais, incluindo decisões bloqueadoras e ausência de duplicação.
- Somente documentação/preparação em branch própria, PR para revisão; nenhuma implementação SPEC01, merge, deploy ou mudança de proteção nesta tarefa.
