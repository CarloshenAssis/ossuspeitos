# Regressão final independente — Fase 2

Fonte da matriz: `a8e6db62628ccfbbd8b08d0427eb039767e27cfc`; checkout isolado `/workspace/phase2-final-tests` criado por `git archive`. Godot `4.4.1.stable.official.49a5bc7b6` explícito pelo ambiente homologado. **44/44 suítes GDScript, 25/25 cenários multiprocesso e 4/4 auxiliares passaram.**

Identidade verificada em 182 arquivos de runtime/assets/testes/configuração: SHA-256 `ddab67570a06b70d07692b7f4d3573c91fd98d589c71c1598ebeefad68b3f8d8`, nenhuma diferença contra o commit. Importação completa X11 Compatibility por software terminou 0, sem SCRIPT ERROR, Parse Error ou ERROR. O editor reformatou `project.godot`; seu conteúdo exato foi restaurado do commit antes da certificação. Os três primeiros cenários e as 44 suítes foram repetidos após essa restauração, substituindo os resultados preliminares.

## Matriz multiprocesso e auxiliares

Cada linha exige exit 0, marcador positivo específico e ausência de SCRIPT/Parse Error; os três casos novos também exigem zero ERROR de engine em todos os logs. Portas exclusivas 44000–44280; execução sequencial, exceto confirmação inicial em portas distintas e suítes unitárias sem transporte. Tempos são duração observada do teste, não benchmark.

| Caso | Configuração | Resultado | Segundos |
| --- | --- | --- | --- |
| `network_smoke` | padrão | PASS | 3.14 |
| `combat_network` | padrão | PASS | 6.1 |
| `combat_network8` | COMBAT_CLIENTS=8, COMBAT_EXTENDED=true | PASS | 29.04 |
| `round_network` | padrão | PASS | 4.34 |
| `round_adversarial` | padrão | PASS | 4.29 |
| `spectator_reveal_network` | padrão | PASS | 3.99 |
| `desktop_local_match` | padrão | PASS | 19.04 |
| `menu_flow` | padrão | PASS | 61.08 |
| `sync_network_local` | PROFILE=local, SEED=1, STALL=false | PASS | 19.14 |
| `sync_network_rtt50` | PROFILE=rtt50, SEED=1, STALL=false | PASS | 19.23 |
| `sync_network_rtt100` | PROFILE=rtt100, SEED=1, STALL=false | PASS | 19.24 |
| `sync_network_rtt200` | PROFILE=rtt200, SEED=1, STALL=false | PASS | 20.2 |
| `sync_network_rtt80` | PROFILE=rtt80, SEED=1, STALL=false | PASS | 19.2 |
| `sync_network_rtt150j` | PROFILE=rtt150j, SEED=3, STALL=false | PASS | 20.19 |
| `sync_network_stall` | PROFILE=rtt150j, SEED=5, STALL=true | PASS | 20.25 |
| `campaign_local` | PROFILE=local, SEED=1 | PASS | 83.35 |
| `campaign_rtt150j` | PROFILE=rtt150j, SEED=4 | PASS | 92.2 |
| `adverse_cases` | SEED=1 | PASS | 163.46 |
| `rooms_network` | padrão | PASS | 26.54 |
| `rooms_adversarial` | padrão | PASS | 9.2 |
| `rooms_resilience` | padrão | PASS | 26.87 |
| `phase10_mutation` | padrão | PASS | 79.72 |
| `phase2_network_local4` | PHASE2_CLIENTS=4, PHASE2_ROUNDS=1, PROFILE=local | PASS | 13.17 |
| `phase2_network_rtt200` | PHASE2_CLIENTS=4, PHASE2_ROUNDS=1, PROFILE=rtt200 | PASS | 20.24 |
| `phase2_network_local8x3` | PHASE2_CLIENTS=8, PHASE2_ROUNDS=3, PROFILE=local | PASS | 39.23 |
| `gameplay_integration` | padrão | PASS | 6.4 |
| `phase2_network_wrapper` | padrão | PASS | 0.17 |
| `gameplay_integration_wrapper` | padrão | PASS | 0.13 |
| `physics_backend_lab` | padrão | PASS | 2.33 |

Os cenários novos comprovaram no transporte real porta fechada/aberta em movimento e tiro, disputa de objeto, pegar/soltar/empurrar, eventos sonoros autorizados sem duplicação, recarga, corpo inspecionado privadamente, pedidos mortos/distantes recusados, término e restauração entre três rodadas. Marcador por rodada: `door=1 prop=1 sound=1 combat=1 inspection=1`; cada cliente confirmou sua execução.

Os auxiliares incluem a cena antiga de 96 verificações seguida de servidor+4; lifecycle antigo em cena/combate/campanha; lifecycle novo com status 37 e TERM 143 preservados e filhos reaped; e laboratório nativo Godot Physics/Jolt.

## Diagnósticos preservados

- **Não se afirma zero ERROR global.** Os testes antigos exercitam mensagens hostis, versão antiga e mutações deliberadas. Seus erros esperados continuam nos logs.
- Comparação com os logs brutos da Fase 1 confirmou as mesmas famílias: `round_network` apresenta 1 RPC para peer desconhecido; `round_adversarial`, 17 mensagens entre spoof recusado, argumentos inválidos e peer desconhecido; `desktop_local_match`, 1 RPC com peer já desconectado. Somente IDs numéricos diferem. Essas condições não foram classificadas como corrigidas.
- Testes de protocolo registram `ERROR: JOIN_REJECTED ... protocol_version` propositalmente; testes de mutação detectaram os quatro defeitos e registraram a falha esperada do cenário alterado/encerramento dos clientes. Nenhum SCRIPT ERROR ou Parse Error foi observado.
- As 44 suítes não emitiram ERROR de engine/script/parse. Permanecem somente os três avisos antigos de ObjectDB nos fixtures `arena_visuals`, `avatar_facing` e `combat_feedback`. Nenhum cenário multiprocesso emitiu aviso ObjectDB ou recursos em uso, inclusive os perfis com atraso e NetDelayPeer.
- O laboratório Jolt atingiu o estado de repouso esperado, mas emitiu uma vez `Jolt Physics job system exceeded the maximum number of jobs`. Foi preservado e não invalida a comparação funcional, porém impede tratar esta execução como benchmark limpo. Jolt não foi ativado na produção.

## Auditoria de processos e correção do registro

Antes de qualquer limpeza externa, cada grupo de processos do harness foi inspecionado por PID/PPID/PGID/estado/comm/argumentos: zero Godot vivo após cada término. O audit final global também encontrou zero Godot vivo e nenhum zombie novo. Os oito processos defunct já existentes sob PID 1 permaneceram; não foram criados por esta execução nem tratados como processos vivos. Não houve pkill amplo. Os testes específicos de lifecycle validaram diretamente os PIDs dos filhos antes de sair.

Uma associação inicial de nomes no runner executou um teste normal extra de quatro clientes no lugar do helper de lifecycle novo. A inconsistência foi detectada antes desta entrega; o script correto `phase2_network_wrapper_test.sh` foi executado separadamente (PASS, exit 37/TERM 143/filhos reaped), e a linha correspondente do resumo foi substituída pelo resultado real. Logs brutos iniciais permanecem disponíveis.

## Correção de áudio posterior à matriz

O coordenador acrescentou `35f219b22becac779256b28712a80ce14268d43c` depois de congelar a fonte da matriz. Seu delta de runtime trata categoria de recarga/volume de combate; **a matriz completa acima pertence a a8e6db6**, não a esse commit posterior. Verificação independente focada no checkout com runtime idêntico ao commit novo: `spatial_audio_test.gd` PASS, 33/33 checks, zero erro de engine/script/parse e nenhum aviso de recurso. O coordenador mantém sua própria execução completa das 44 suítes para esse delta.

## Reprodução e limites

```bash
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
python3 tests/run_phase2_unit_tests.py --logs /tmp/suspeitos-phase2-unit
PHASE2_CLIENTS=4 PHASE2_ROUNDS=1 PROFILE=rtt200 bash tests/phase2_network_test.sh
PHASE2_CLIENTS=8 PHASE2_ROUNDS=3 PROFILE=local bash tests/phase2_network_test.sh
bash tests/phase2_network_wrapper_test.sh
bash tests/physics_backend_lab_test.sh
```

Comandos, variáveis, marcador, duração, classificação de cada erro e caminhos de logs estão em [final-regression-summary.json](final-regression-summary.json). Logs completos locais: `/workspace/.ossuspeitos-state/phase2/final/`. Os resultados hospedados de CI, exports Windows/Web e container serão informados separadamente pelo coordenador; nenhum deles é inferido desta certificação local. Áudio headless não certifica percepção humana; llvmpipe não certifica GPU física; atrasos na aplicação não equivalem a perda física TCP. Nenhum merge ou deploy foi realizado por este executor.
