# SPEC16 — integração e certificação

A sequência `tests/scenes/phase2_network.tscn` usa um subclass somente de teste de NetworkApp, herdando todos os RPCs de produção sem sobrescrevê-los. Duas RPCs de barreira existem apenas em tests/, excluídos dos builds de produção. Servidor prepara posições/itens oficiais; portas, props, coleta, tiros, recarga e investigação continuam atravessando comandos reais, época, filas, validação e ACK.

Cobertura: porta fechada bloqueia movimento/dano e aberta permite os mesmos; dois atores disputam posse, drop real com queda/impacto, push, recusa por distância/replay sem som falso, passos/recarga autorizados, tiros causam morte/corpo, dois leitores recebem somente suas inspeções, morto/distante recusados, tiros encerram a rodada e a campanha recupera corpos/inspeções/portas/épocas. Todas as observações verificam bloqueadores da previsão versus estado público recebido.

Matriz de desenvolvimento antes da compactação:4local/4RTT200/8×3local PASS,28/28/84assertivas e todos os marcadores dos clientes, zero engineERROR e shutdown completo; evidence/network-development.md. Após o codec15,4RTT200 também PASS. Wrapperlifecycle comprova status37, TERM143 e filhos reaproveitados/encerrados. A matriz final será registrada no relatório e evidências correspondentes, sem inferir execução de um commit posterior desses resultados.

Suíte completa posterior aoSPEC15:44/44GDScript PASS. Cena gráfica carregada separada:8avatares+corpo+23objetos/12vozes, seis runs verdes e zero alteração de mira/estado oficial, usando llvmpipe. A fixture gráfica injeta DTOs; o transporte acima comprova autorizações; nenhum deles substitui playtest humano.

Novo workflow `gameplay-phase2` tem contents:read, importação gráfica completa com gate estrito, toda suíte, laboratórioPhysics/Jolt, lifecycle,4local/4RTT200/8×3. Workflows existentes e suas assertivas permanecem; expectativas da versão foram ajustadas para12. Não há job de publicação no novo workflow. ExportsWeb/Windows/container e sonda remota continuam nos workflows existentes; a sonda pode registrar recusa esperada do protocolo antigo em produção. Nenhum deploy acompanha esse resultado.

Revisão independente final, regressão multiprocesso completa, CI e PR estão em fechamento; consultar final-report.md/PR para status final efetivamente observado. Main e proteções não foram alteradas; merge e publicações não fazem parte da missão.

Fechamento local:44/44suítes e29/29cenários da regressão independente PASS noarquivo limpoa8e6db6. Após revisão final, recarga remota corrigida para categoria combate;44/44suítes e33checks áudio PASS em35f219b, com áudio também reexecutado independentemente. Ver evidence/final-regression.md, evidence/final-unit-results.json e evidence/review-resolution.md. CI hospedado é evidência separada noPR doSHAfinal.
