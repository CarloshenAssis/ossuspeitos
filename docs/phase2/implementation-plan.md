# Fase 2 Implementation Plan

> **For agentic workers:** Use executing-plans for inline implementation; independent agents research, baseline and final review per AGENTS.md. Steps use checkbox syntax.

**Goal:** Entregar SPEC09–16 funcionais na mansão sem merge/publicação.
**Architecture:** Estado autoritativo por MatchRoom; volumes analíticos compartilhados e apresentação local. Reutilizar comandos/ACK, corpos, áudio sintetizado e animação procedural.
**Tech Stack:** Godot4.4.1 GDScript, WebSocket/TCP, Bash/Python, GitHub Actions.
**Spec:** docs/phase2/master-spec.md; desenho docs/phase2/design.md.

## Global Constraints

- Não fazer merge main, auto-merge, Pages/Railway, alterações de proteção ou infraestrutura paga.
- Preservar testes e gameplay01–08; nenhuma dependência/asset sem licença.
- Versão de protocolo12 intencional e testada, sem alteração acidental dos RPCs.
- Sem NPC no modo principal, habilidades de papel indefinidas ou mudança de velocidade/vertical.

## Review Focus

- Transição de sala/rodada/época com comandos de objeto em trânsito: recusados sem alterar nova instância.
- Dois atores e objeto ocupado: no máximo um dono, liberação segura em morte/desconexão.
- Snapshot/evento público com papel privado: allowlist e teste de ausência de segredo.
- Fechar porta/mover prop sobre jogador/arma: mesmos AABBs para tiro e movimento, recusa de sobreposição.
- Reconexão/queda de áudio/reset visual: deduplicação limitada e lifecycle sem nós/processos abandonados.

### Task 09: Interações físicas autoritativas
**Files:** shared/environment_rules.gd, server/interaction_authority.gd, shared/net_sync.gd, shared/movement_rules.gd, shared/player_prediction.gd, shared/network_config.gd, server/match_room.gd, server/combat_authority.gd, shared/network_app.gd, client/arena_view.gd; tests/interaction_authority_test.gd e laboratório.
**Interfaces:** comandos interact(id,target,verb); room.interactions; public snapshot e blockers por instância; detalhes finais auditados no relatório09.
- [ ] Teste RED: porta aberta/fechada, ownership concorrente, alcance/LOS, morto/stale/replay/rate, payload não pode informar transform.
- [ ] Implementar volumes/props limitados, passagem/tiro consistentes, posse/liberação/reset e clienteE.
- [ ] GREEN: testes09 e regressões movimento/previsão/combate; laboratórioPhysics/Jolt; evidência e commitSPEC09.

### Task 10: Áudio espacial
**Files:** shared/sound_event.gd, client/spatial_audio_controller.gd, client/sfx_bank.gd, client/menu_settings.gd, client/desktop_menu.gd; integrar NetworkApp/ArenaView/authority; tests/spatial_audio_test.gd.
**Interfaces:** evento sanitizado(id,round,kind,position), catálogo allowlist, consumo deduplicado por cliente; volume por categoria.
- [ ] RED: origem oficial, distância/oclusão simples, volumezero, limite/prioridade e duplicados/reset.
- [ ] Implementar passos/porta/queda/tiro/recarga sem duplicar áudio anterior, sem voz/arquivo remoto.
- [ ] GREEN: suítes de áudio/menu/combate e sem dispositivo; evidência e commitSPEC10.

### Task 11: Ações e transições visuais
**Files:** client/character_animator.gd e módulo focado de ações; client/arena_view.gd; tests/character_actions_test.gd.
**Interfaces:** apresentação lê ações oficiais e vida/velocidade; nunca escreve simulação/câmera.
- [ ] RED: prioridades/interrupções, morte/reconexão e equivalência30/60/120FPS.
- [ ] Implementar poses procedurais incrementais de interação/tiro/recarga/impacto/morte.
- [ ] GREEN: animação existente/câmera/combate e novos testes; evidência e commitSPEC11.

### Task 12: Investigação
**Files:** server/investigation_authority.gd, shared/investigation_rules.gd; integrar corpos e interações; tests/investigation_test.gd.
**Interfaces:** mesma intenção bounded; servidor retorna fato público permitido só ao solicitante; sem informação do assassino.
- [ ] RED: corpo oficial, dois leitores, foraalcance/morto/sempermissão, sigilo, reset/reconexão.
- [ ] Implementar inspeção útil com identidade pública/circunstância pública, sem novos poderes.
- [ ] GREEN: privacidade/corpos/reveal/room e novos testes; evidência e commitSPEC12.

### Task 13: Mansão interativa
**Files:** definições de ambiente e apresentação; tests/environment_presentation_test.gd.
**Interfaces:** interação/hint desde snapshot público; nenhuma geometria paralela.
- [ ] RED: objetos presentes, indicador e recusa, reset; volumes/tiro coerentes.
- [ ] Integrar distribuição limitada, leitura clara de porta/objeto e ambientação nativa sem bloquear injustamente visão.
- [ ] GREEN: quatro/oito clientes, graphicalsmoke e layout; evidência e commitSPEC13.

### Task 14: IA/diálogos
**Files:** docs/phase2/14-ai-dialogue.md.
- [ ] Auditar reutilização de autoridades, estados e diálogo privado.
- [ ] Comparar alternativas nativas/StateCharts/DialogueManager versão compatível.
- [ ] Documentar necessidade real, decisão e custos; sem NPC/runtime desnecessário; commitSPEC14.

### Task 15: Otimização e compatibilidade
**Files:** tests/phase2_benchmark.gd, docs/phase2/15-performance.md.
- [ ] Medir frame/CPU/memória/objetos/eventos/snapshots onde possível comparados baseline.
- [ ] Corrigir custo excessivo sem enfraquecer testes; limitar objetos/eventos/processamento.
- [ ] Executar regressões e builds disponíveis; registrar limites GPU/Android/macOS; commitSPEC15.

### Task 16: Integração/playtest
**Files:** tests/phase2_integration_test.gd, tests/phase2_network_test.sh/coordinator, .github/workflows/gameplay-phase2.yml, docs/phase2/final-report.md.
- [ ] RED: integração real ações09–13, quatro/oito jogadores, salas/segredos/replay/200ms/reset/cleanup.
- [ ] GREEN: todas suítes existentes/novas + multiprocesso, Web/Windows/container/CI e smokegráfico viável.
- [ ] Revisão independente fresca, corrigir achados importantes com teste; registrar matriz/commits/limites e commitSPEC16.
- [ ] Push/PR consolidado, esperar checks; nenhum merge/publicação.
