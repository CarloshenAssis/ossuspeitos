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
- Task 4: complete (commits e234aeb..4ff857f, review clean). SPEC04: precisão/bloom autoritativos e cone esférico estável; 6216 checks e laboratório12 passaram. Combate4 passou na repetição e8extended passou; timeout inicial CONTEST sem causa demonstrada registrado. Relatório04-calibration.md.
- Task 5: complete (commits4ff857f..150b543 + correção28d18b6, review clean apósfixround1). SPEC05: nove suítes, spectator4 e gráfico aprovados; correção de prontidão validada coordinator37/netcode266/authority86 e combate4/8extended sequenciais aprovados. Revisões independentes de apresentação e harness PASS.
- Task 6: complete (commits6ff4bed..9d158bf, review clean). SPEC06: perfis isolados/localizados, baseline preservado;35 suítes, smoke4 e sync aprovados. Benchmarkquietllvmpipe p95 baseline24.429ms/low12.006/high23.220. Captureverificouhighlegível após restringirfiltro a texturas; sombrasnãoadicionadas.
- Task 7: complete (commits9d158bf..44a0364, review clean). SPEC07: telemetriaopcional limitada, nenhuma mudançaDTO/protocolo. Testes focados, sync local/rtt200, round, salas/adversarial/resiliência e combate4/8extended comtelemetria passaram. Overheadsyntético4peers +7.4%/+6.2%, padrãooff.
- Task 8: complete (commits44a0364..3e40dba + CI959dd3f, review clean apósfixround1). Cena96, integração4, campanha8x3/lifecycle PASS; revisão de branch completa PASS; regressão final37/37 GDScript e22/22 multiprocesso PASS. CI hospedado final é verificado separadamente no PR.

## Limitação operacional observada
Após o reinício do ambiente, quatro servidores locais antigos do teste SPEC00 menu_flow permaneceram destacados (portas 33072/33075/33076/33077). Confirmados por cmdline, proprietário e logs; encerrados individualmente, sem atingir processos externos. A limpeza de descendentes do harness requer atenção na certificação final.

## CI de checkpoint
Run39689745482 (SPEC01–03): match-tests/menu-tests/rooms-tests passaram; network-tests falhou no cenário8extended. netcode-tests também passou na conclusão; resultado geral FAILURE pelo network-tests. Download do log detalhado redireciona para blob storage bloqueado neste ambiente; não considerar CI aprovado. Falha intermitente CONTEST também observada localmente; investigação de causalidade do harness em andamento, sem enfraquecer assertivas.

Task5: fix round1/5 concluída, três achados resolvidos — reset imediato após health0, ownership CharacterRig e aplicação ao vivo reduce_motion. Novos regressivos passaram; gate combate4 depende da correção separada de prontidão de época identificada em combat-flake-research.md.

Task5: minor (resolvido documentalmente): relatório externo dizia teste de strength0 direto; cobertura real é disable integrado. Redação corrigida para disabled presentation identity.

Correção adicional28d18b6: ações de teste agora aguardam barreira de previsão/época, sem relaxar timeouts/assertivas. Teste determinístico reproduziu falha antiga;4/8network passaram. Causa histórica doCI8 não atribuída semlogs. Review PASS compliance/quality.

Ruling: o perfil high entregue manterá sombras de sala desligadas, com apenas qualidade de material opcional — capturas llvmpipe ficaram ilegíveis mesmo após reduzir opacidade; a causa específica não foi comprovada — custo se inadequado: reavaliar sombras/geometria/driver com GPU representativa antes de reintroduzir a opção.

SPEC06 revisão PASS compliance/quality/evidence. O escurecimento persistiu sem sombras, logo a causa específica não foi atribuída a elas; high final preserva todas as luzes e aplica filtro apenas a materiais com albedo_texture. Captura final legível; GPUreal pendente.

Regressão final em3e40dba:37/37 suítesGDScript PASS; semSCRIPT/Parse/ERROR. AvisosObjectDBpreexistentes nos fixtures arena_visuals/avatar_facing/combat_feedback preservados no relatório. Matrizmultiprocesso22variantes emexecução. Workflow novo independente gameplay-specs; existentes/publicação intactos.

## Fechamento local
Todas as oito tarefas implementadas e revisadas.37 suítes e22 variantes finais PASS; fingerprint3d6a92a21be423b9232910037039a0b5a9710cea1a1bb5ed1060a6b848f304f7 confirmado e zero processos próprios Godot vivos. Evidências/relatório final commitados; aguardando push/PR e checks hospedados finais, sem inferir exports por testes locais. Main permanece fora da integração.

## CI final e importação limpa
PR31 aberto com permissões reais de push/PR confirmadas; main dd15ff2 inalterada e autoMergeRequest=null. O primeiro novo check falhou na importação limpa por oito erros upstream de preview GLB no renderer dummy4.4.1. Corrigido em8e880f4: somente novo job, Xvfb/Mesa/software e --import completo; gate estrito preservado. Repro freshheadless red/freshgraphics green e sete suítesfresh PASS, revisão scoped PASS. Runtime continua3e40dba;37+22 não repetidos por mudança somenteCI. Checks hospedados da revisão atual ainda em acompanhamento; nenhum merge/publicação.
