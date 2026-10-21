# SDD ledger — plan: docs/gameplay-research/implementation-plan.md

## Missão e estado
A missão vigente é [autonomous-mission.md](autonomous-mission.md), autorizada pelo usuário em 2026-10-21. Ela substitui as pausas entre SPECs do plano anterior: integração automática somente na branch de trabalho, nunca main. PR #30 permanece independente; esta branch descende do mesmo commit de auditoria cfe260b00a6c95f1aacb42c4c0764921213eb493, sem copiar/cherry-pick dos documentos.

Branch: codex/gameplay-specs-01-08. Base de código: dd15ff2ab29d5e67fccedc41c431c30eb7e32c6d.
SPEC00: todos os nove checks exigidos do PR30 concluídos com SUCCESS em cfe260b00a6c95f1aacb42c4c0764921213eb493; deploy-pages SKIPPED. Conferido via GitHub em 2026-10-21 22:38 UTC. Sem merge do PR30.
Proibido: merge main, deploy, alterar políticas/credenciais/publicação, copiar GPL/assets.
Ambiente: Godot 4.4.1; logs externos /workspace/.ossuspeitos-state/mission-sdd/.

## Preflight — tarefas e fronteiras compartilhadas

| SPEC | Produz/consome | Consistência verificada |
| --- | --- | --- |
| 01 | MovementRules/config compartilhada → replay servidor/cliente | Preservar 5 m/s, aceleração/frenagem 18 e Y=1; não criar input vertical/sprint |
| 02 | PlayerPrediction/RemoteInterpolator/NetSync + harnesses | Usa simulação 01; buffers/ACK/época existentes, novos perfis não mudam protocolo |
| 03 | WeaponDefinition/InventoryAuthority/CombatAuthority | Preservar pistola, dano, munição e papéis; catálogo único |
| 04 | Configuração/regras 03 → spread/feedback servidor | RNG no servidor, cliente nunca escolhe trajetória |
| 05 | Apresentação ArenaView → câmera/animação | Consome eventos 04; não escrever mira oficial ou colisão |
| 06 | Materiais/luzes/efeitos 05 + benchmark | Compatibility; perfil baseline preservado, físicas oficiais analíticas |
| 07 | Instrumentação/limites de rede 02 → integração | Não recriar previsão; sem migração TCP ou DTO incompatível |
| 08 | Integração 01–07 + suites atuais | Regras efetivas de partida, sem certificar recursos sociais inexistentes |

| Par | Fronteira comum | Resolução |
| --- | --- | --- |
| 01/02/07 | MovementRules, simulação e ACK | Implementação sequencial, testes replay e adversários após cada mudança |
| 03/04 | WeaponDefinition, CombatRules, CombatAuthority | Um catálogo; validar campos adicionais sem substituir pistola |
| 04/05 | ArenaView e eventos de tiro | Efeito visual não decide dano; um escritor por transform |
| 05/06 | ArenaView, MenuSettings, efeitos | Opções limitadas, garantir defaults e saída headless |
| 02/07/08 | Harnesses, perfis, snapshots | Preservar testes existentes e executar matriz final no mesmo commit |

## Decisões reversíveis
Ruling: configuração de movimento será recurso compartilhado distribuído com o build, sem edição remota ou escolha do cliente — manter replay idêntico sem mudar protocolo — custo se inadequado: configurar valores em runtime exigirá desenho de handshake e nova validação.
Ruling: preservar regras de dano/papéis atuais e não introduzir armas sociais, DOWNED, salto ou rampas nesta missão — o usuário exige preservar regras existentes e não alterar automaticamente simulação vertical — custo: esses itens da Master SPEC original permanecem lacunas explicitamente listadas.
Ruling: melhorias gráficas usarão perfis opcionais medidos, mantendo baseline como default quando não houver GPU representativa — preservar desempenho/Compatibility e servidor headless — custo: certificação visual/performance real fica pendente.

## Progresso
- Task 1: complete (commits ac4f0ed..669b109, review clean). SPEC01: recurso validado, aceleração/frenagem separadas; testes unitários + smoke/sync servidor e 4 clientes aprovados. Vertical/sprint adiados. Relatório 01-movement.md.
- Task 2: complete (commits 669b109..ae05afa, review clean). SPEC02: correções de época/ações, perfis 50/100/200 e métricas precisas; 266 checks, smoke e sync com jitter/stall aprovados; leak do fixture eliminado. Relatório 02-prediction.md.
- Task 3: complete (commits ae05afa..65992e3, review clean). SPEC03: catálogo novo por instância, cópias validadas e composição confiável; 32 suítes GDScript e combate 4/8extended aprovados. Relatório 03-combat.md.
- SPEC04: próxima etapa; brief externo spec04-brief.md preparado.
- SPEC05: pendente.
- SPEC06: pendente.
- SPEC07: pendente.
- SPEC08: pendente.
