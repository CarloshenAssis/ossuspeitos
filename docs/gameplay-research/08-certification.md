# SPEC 08 — integração e certificação local

A cena `tests/scenes/gameplay_integration.tscn` integra as classes de produção
`MatchRoom`, `RoundAuthority`, `AuthoritativeWorld`, `PlayerPrediction`,
`InventoryAuthority`, `CombatRules`, `CombatAuthority` e `ArenaView`.
Não substitui a mansão, o controlador ou o transporte. O wrapper
`tests/gameplay_integration_test.sh` exige a cena e servidor + quatro clientes
reais pelo harness existente de combate antes de imprimir seu marker final.
`RUN_CAMPAIGN=true` acrescenta o campaign existente, oito clientes e três rodadas;
não existe implementação paralela de campaign.

A cena usa seed 8 e tempos explícitos, mantém os mesmos quatro peers e verifica
lobby, PRONTO, contagem, rodada, movimento/replay, pickup de arma e munição,
recarga, disparo oficial, rejeição de replay, morte, resultado e volta ao lobby.
Verifica que uma mudança de época descarta ação/mira pendentes, que movimento
real alimenta spread configurado e bloom, e que os três perfis gráficos e
movimento visual conservam origem/direção oficiais. Confere allowlist do mundo,
ausência de inventário/papel no pickup público e isolamento de métricas/sala.
A integração de rede mantém as asserções existentes de privacidade e shutdown.

## Resultado por SPEC

| SPEC | Implementado e integrado | Limites preservados |
| --- | --- | --- |
| 01 | Resource validado, aceleração/desaceleração compartilhadas | Movimento XZ; sem salto, gravidade ou sprint |
| 02 | Replay/reconciliação, descarte por época, buffers limitados | WebSocket/TCP; sem rollback ou previsão de dano |
| 03 | Catálogo confiável e autoridades de inventário/combate | Somente pistola comum; sem armas sociais especiais |
| 04 | Precisão configurável, bloom, cone e hitscan oficial | Defaults de precisão zero; sem projétil, penetração ou rewind |
| 05 | Bob/sway em pivô separado, redução de movimento, tracer corrigido | Sem ADS/DOWNED; aprovação humana da sensação pendente |
| 06 | Perfis low/baseline/high locais, benchmark Compatibility | High filtra texturas; não muda luzes; sem certificação GPU |
| 07 | Telemetria opcional limitada por mundo | Desligada por padrão; bytes Variant não são bytes TCP |
| 08 | Cena funcional e wrapper obrigatório server+4, campaign opcional | Loopback/headless; não certifica qualidade visual ou plataformas |

## Evidência e reprodução

Engine homologado: Godot 4.4.1 `49a5bc7b6`. Fonte o ambiente antes de cada
execução. Evidências locais ficam em
`/workspace/.ossuspeitos-state/mission-sdd/spec08/`.

```bash
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
"$GODOT_BIN" --headless --path . --script tests/gameplay_integration_test.gd
TEST_LOG_DIR=/tmp/spec08 RUN_CAMPAIGN=true bash tests/gameplay_integration_test.sh
# Servidor e cliente locais de desenvolvimento, terminais separados:
"$GODOT_BIN" --headless --path . -- --mode=server --bind=127.0.0.1 --port=8080
DISPLAY=:99 "$GODOT_BIN" --audio-driver Dummy --path . -- --mode=client --url=ws://127.0.0.1:8080 --client-id=local
# Benchmark gráfico, não usar headless como evidência de renderização:
DISPLAY=:99 "$GODOT_BIN" --audio-driver Dummy --rendering-method gl_compatibility --path . tests/scenes/graphics_benchmark.tscn -- --profile=baseline
```

A primeira execução funcional da cena saiu 1 com cinco asserções: o fixture
capturou a câmera antes de escrever seu rig inicial e tentou recarregar sem
coletar reserva. A correção inicializa a apresentação e coleta uma caixa real
pela autoridade. Não houve alteração de produção ou enfraquecimento do contrato.
A tentativa anterior de executar a cena inexistente é apenas evidência de
arquivo ausente, não um ciclo TDD funcional. A cena final passou 96 verificações,
sem erro de runtime ou warning de saída. O fluxo de 12 comandos mediu 960 bytes
Variant (12 × 80), fila máxima 1, zero duplicatas; o outro mundo ficou sem comandos.
Esses números são deste cenário em processo, não bandwidth de rede.
O wrapper obrigatório server+4 passou, assim como `RUN_CAMPAIGN=true` com
`CAMPAIGN_TEST_OK profile=local seed=8 clients=8 rounds=3` e sessão de controle
na mesma porta. O fixture final também compara posição antes de reconciliar,
exige movimento visual ativo com arma equipada antes dos resets e conserva
snapshot/ACK/telemetria de uma segunda sala ocupada. O reset visual de morte
usa o DTO privado do próprio peer local após dano pela autoridade; a morte
por hitscan é verificada separadamente no alvo.

A revisão global no HEAD final e os links de CI/PR serão acrescentados pelo
coordenador da missão; não são declarados executados por esta etapa. O wrapper
preserva o exit original de cada comando, cria diretório único com `mktemp` e
reutiliza cleanup de PIDs próprios dos harnesses. O wrapper rastreia seu filho
ativo, encaminha TERM/INT e aguarda o encerramento. O teste determinístico
`gameplay_integration_wrapper_test.sh` comprovou propagação de exit 37 e TERM
durante cena, combate e campaign, sem sobrevivência de filho/descendente. Nenhuma sondagem de produção.

## Comparação e limitações

Não foi feito novo benchmark gráfico no SPEC08. A comparação válida é a do
SPEC06: Godot 4.4.1, Xorg dummy, Mesa llvmpipe LLVM 19.1.7, CPU AMD EPYC 9V74,
960×540, cena fixa sem personagens. Antes p95 23,112 ms; depois baseline
24,429 ms, low 12,006 ms, high 23,220 ms. São tempos de parede por quadro em
renderização por software; não FPS nem tempo isolado de GPU. A instrumentação
SPEC07 acrescentou 7,4%/6,2% no microbenchmark único de lotes 2/8, sem ganho de
throughput alegado. Ver relatórios 06 e 07 para amostragem e unidades completas.

Continuam fora da certificação: Android/Web/export, GPU real, rede remota,
latência/perda física, conforto e qualidade visual humana, armas sociais,
ressurreição, DOWNED e movimento vertical. Avisos de saída preexistentes de
áudio/ObjectDB em testes antigos continuam registrados nos relatórios anteriores;
o novo fixture aguarda 0,6 s para drenar áudio curto após equipar. A corrida histórica do harness de combate
foi tratada antes desta etapa pela barreira INITIAL e gate de elegibilidade;
essas proteções foram preservadas. Falhas novas observadas na revisão global
precisam constar aqui antes de afirmar ausência de regressões.

Código de integração original, sem importação de código, assets ou mídia de
referência. Licenças/referências conceituais permanecem no
[registro existente](license-register.md); nenhuma dependência nova ou código GPL.

## Fechamento da regressão global

Em3e40dba, com runtime idêntico após os commits de CI/documentação:37/37 suítes GDScript e22/22 cenários multiprocesso PASS; cena96, integração4, lifecycle e importação PASS. Revisão da branch sem achado importante. Três fixtures antigos avisam ObjectDB no encerramento; detalhes e limites preservados no [relatório final](final-report.md) e [evidência estruturada](evidence/final-test-summary.json). Exports/container e estado hospedado final devem ser conferidos nos checks do PR; não houve publicação.
