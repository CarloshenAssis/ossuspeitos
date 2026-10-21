# Suspeitos — entrega dos SPECs 01–08

Branch `codex/gameplay-specs-01-08`, baseada na auditoria do PR #30 (`cfe260b`). Implementação de integração: `3e40dba`; commits posteriores de CI/documentação não mudam o runtime testado. A branch conserva a ancestralidade da auditoria, sem cherry-pick/cópia paralela. O PR consolidado depende do histórico do PR #30; nenhum deles foi mesclado.

## Resultado implementado

| SPEC | Entrega | Commit |
| --- | --- | --- |
| 01 | Movimento compartilhado configurável e validado; defaults 5/18/18 preservados | `669b109` |
| 02 | ACK/época seguros, limpeza de ações/mira, métricas e perfis 50/100/200 | `ae05afa` |
| 03 | Catálogo confiável, cópias validadas, composição e ordenação de combate | `65992e3` |
| 04 | Spread esférico estável, precisão por movimento, bloom/recuperação e laboratório | `4ff857f` |
| 05 | Bob/sway separado, resets, preferências ao vivo, correções de tracer/ownership | `150b543` |
| 06 | Perfis gráficos isolados/localizados, benchmark e captura legível | `9d158bf` |
| 07 | Telemetria opcional limitada, schema sem segredos e evidência4/8 clientes | `44a0364` |
| 08 | Cena integrada com 96 checks, wrapper obrigatório com 4 clientes, campanha com 8×3 e cleanup | `3e40dba` |

Correção adicional `28d18b6`: o teste de combate não enfileira ações antes de a previsão receber a época da rodada. Regressão determinística reproduziu a perda; a correção usa a barreira existente, sem enfraquecer timeout/assertivas. O CI do checkpoint 6ff4bed passou os cinco jobs de rede. A falha histórica de oito jogadores em e234aeb permanece sem causa comprovada, pois seu log redirecionou a armazenamento inacessível. O mecanismo reproduzido não prova a causa daquela execução.

## Validação final

- **37/37 suítes GDScript PASS**, sem SCRIPT ERROR, Parse Error ou ERROR de engine; avisos de áudio/ObjectDB discriminados abaixo.
- **22/22 cenários multiprocesso PASS**:19 originais e sync50/100/200 adicionais, incluindo campanhas8×3 local/jitter, casos adversos, privacidade, salas e quatro mutações detectadas.
- Cena integrada **96 verificações**, wrapper obrigatório **servidor+4** e lifecycle/exit37/TERM em cena/combate/campanha PASS.
- Importação completa gráfica por software e sintaxe YAML/Bash do novo CI PASS. Revisão independente da branch PASS, sem achado importante.
- Fingerprint de runtime/testes confirmado após a execução; nenhum processo Godot próprio de teste ficou vivo.
- CI completo do PR, exports e container: consultar checks hospedados; não são inferidos dos testes locais.

Evidências estruturadas: [final-test-summary.json](evidence/final-test-summary.json). Revisão independente completa: [final-branch-review.md](evidence/final-branch-review.md), sem achado importante. Logs completos locais em `/workspace/.ossuspeitos-state/mission-sdd/final/`; logs do CI ficam nos artifacts dos workflows. A suíte exige exit correto e marcador final; erros de script/parse são inspecionados. Três fixtures antigos (`arena_visuals`, `avatar_facing`, `combat_feedback`) ainda avisam ObjectDB no encerramento durante áudio, também observado no baseline. Não foram ocultados nem classificados como corrigidos.

## Métricas e limites

Godot 4.4.1, X11 dummy/Mesa llvmpipe, AMD EPYC 9V74, 960×540, 120 quadros de aquecimento/300 medidos: p95 antes 23.112 ms; depois padrão 24.429 ms, baixo 12.006 ms, alto 23.220 ms. São observações de tempo por quadro em software; outlier máximo 128.290 ms no padrão e incerteza de host compartilhado estão registrados no [benchmark](06-benchmark.md). Não há certificação de GPU/FPS de hardware. High mantém luzes originais e só filtra materiais texturizados.

Telemetria desligada por padrão. Microbenchmark único com 4 peers: overhead 7.4%/6.2% para lotes 2/8; não é ganho de throughput. Em combate real estendido, últimas observações:4 clientes, 498 pacotes/64.376 bytes Variant/fila 5;8 clientes, 1013 pacotes/130.576 bytes/fila 4. Não são totais de sessão nem bytes de fio TCP. Limites de fila 32, pendentes 90, pacote 8 e orçamento 12 preservados. Perfis de rede atrasam entrega na aplicação sobre TCP, não simulam perda física.

Movimento continua planar; sem salto/sprint/rampas. Pistola mantém dano 34, 6/18 cartuchos, 400 ms, 20 m, recarga 1200 ms e novos parâmetros de precisão zero. Não foram criadas armas sociais, ressurreição, DOWNED, ADS, penetração ou rewind. Validação humana de conforto/visibilidade, Android, GPU física e rede remota continuam pendentes. Exports/Web/Windows/container dependem dos resultados reais dos respectivos checks do PR, não dos testes headless locais.

## Referências, arquivos e execução

As sete referências e seus SHAs/licenças estão no [inventário](license-register.md): FirstPersonStarter(MIT), QuakeIII(GPLv2+), RedEclipse(zlib fontes), Sauerbraten(zlib fontes), TPSDemo(MIT código/CC-BY mídia), WickedEngine(MIT) e ioquake3(GPLv2+). Uso conceitual e implementações próprias; nenhum código, asset ou engine dessas referências incorporado. Assets anteriores mantêm a pendência de procedência da auditoria.

Arquivos centrais: `shared/movement_config.gd`, `movement_rules.gd`, `player_prediction.gd`, `weapon_definition.gd`, `weapon_rules.gd`; `server/weapon_catalog.gd`, `inventory_authority.gd`, `combat_rules.gd`, `combat_authority.gd`, `authoritative_world.gd`; `client/arena_view.gd`, `camera_effects.gd`, `arena_models.gd`, `character_rig.gd`, `menu_settings.gd`, `desktop_menu.gd`; `shared/network_app.gd`, testes novos e `.github/workflows/gameplay-specs.yml`. Relatórios detalhados01–08 ficam neste diretório.

No checkout cloud atual:
```bash
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
bash tests/gameplay_integration_test.sh
RUN_CAMPAIGN=true TEST_LOG_DIR=/tmp/suspeitos-review bash tests/gameplay_integration_test.sh
```
Para jogar num desktop com Godot 4.4.1, abra o projeto/menu e crie partida local. Para servidor de desenvolvimento: `--headless --path . -- --mode=server --bind=127.0.0.1 --port=8080`; clientes usam `--path . -- --mode=client --url=ws://127.0.0.1:8080 --client-id=local`. O display :99 deste host é somente software, não uma sessão desktop remota certificada.

## Integração e proteção propostas

O PR conserva main/publicação intactas, sem auto-merge. O novo job independente `gameplay-specs` só lê conteúdo e valida as novas suítes/integração/perfis. Proposta futura, após conferir o primeiro verde/origem dos checks: PR obrigatório e 10 checks (os nove atuais + gameplay-specs), branch atualizada, conversas resolvidas, bloqueio de force-push/exclusão. Nenhuma proteção foi alterada por API. Merge, Pages e Railway exigem autorização posterior; não fazem parte desta entrega. Os gatilhos existentes da main não foram alterados: uma autorização futura de merge deve considerar que eles podem iniciar publicação automaticamente. Resultados hospedados atuais devem ser consultados nos checks do PR consolidado.

## Decisões tomadas e custo se inadequadas

1. Configuração de movimento distribuída com o build, sem handshake — preserva replay/protocolo; ajuste remoto futuro exige desenho de sincronização.
2. Preservar regras/dano existentes e adiar armas sociais/DOWNED/vertical — evita alterar o jogo nesta missão; esses recursos da visão original continuam lacunas.
3. Perfis opcionais com padrão conservado — preserva Compatibility/servidor; certificação em GPU real fica pendente.
4. High sem novas sombras de sala — experimentos tiveram superfícies ilegíveis, inclusive sem sombras até restringir o filtro a materiais texturizados; reintroduzir sombras exige nova investigação de geometria/driver/GPU.

## Correção da importação limpa no CI

O primeiro gameplay-specs falhou corretamente ao detectar oito erros de prévia GLB do renderizador dummy do Godot 4.4.1. Importação local quente/parcial não os expunha. A reprodução em checkout novo confirmou: --headless --import termina 0, mas gera oito ERROR de textura; importação gráfica completa Compatibility/software termina 0 sem erros, e sete suítes afetadas passaram nesse projeto novo. O commit 8e880f4 acrescenta suporte Xvfb/Mesa somente no novo job e usa --import para aguardar todos os assets. As verificações estritas e os testes headless permanecem; nenhum código de gameplay mudou. A execução Ubuntu/Xvfb é confirmada pelos checks atuais do PR. [Investigação](evidence/clean-import-report.md) e [revisão independente](evidence/clean-import-review.md).
