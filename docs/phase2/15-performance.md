# SPEC 15 — desempenho e compatibilidade

## Método e identidade

Baseline congelada `59926cb74c6861c207ad16f7ad2793ea55bc9995`, extraída em `/workspace/phase2-baseline`; comparação inicial Fase 2 em `4abbe51` (SPECs 09–13), com fingerprint dos diretórios `client/server/shared` em [performance.json](evidence/performance.json). Nenhum fonte de produção foi editado pelo executor destas medições. Godot 4.4.1 oficial, AMD EPYC 9V74, host compartilhado; root e demais agentes suspenderam testes/render/rede durante a sessão de medição. Isso reduz concorrência controlável, mas não elimina variância externa do host.

Logs completos em `/workspace/.ossuspeitos-state/phase2/`: `runtime-baseline.log`, `runtime-current.log`, `graphics-*.log` e capturas `loaded-*.png`. Os scripts novos são `tests/phase2_runtime_benchmark.gd`, `tests/phase2_graphics_benchmark.gd` e sua cena. São medições separadas da suíte unitária, não certificações de desempenho em toda máquina.

## Modelo servidor: quatro e oito participantes

O mesmo script foi copiado para o arquivo baseline. Cada caso cria uma `MatchRoom` real, entra com quatro/oito participantes, inicia rodada, inicializa combate e spawns, envia comandos codificados aceitos pela fila oficial, executa `AuthoritativeWorld.step`, ticks reais de combate/rodada e, quando disponível, `InteractionAuthority.tick` e `SoundEventAuthority.observe_movement`. São 120 ticks de aquecimento + **1200 medidos** por caso. Modelo configura 60 ticks/s e um snapshot a cada três ticks (20 Hz); a execução avança sem esperar o relógio real. Não é um teste de sockets nem comprovação de taxa sob rede.

Estático envia movimento zero. Ativo movimenta os peers 2..N em direção alternada; peer 1 fica no escritório e, somente na Fase 2, alterna pegar/soltar o prop a cada 240 ticks: **seis interações aceitas** incluindo aquecimento. Todos os comandos foram simulados (5280 com quatro peers, 10560 com oito), sem recusas. A carga é comparável para movimento e combate; a Fase 2 deliberadamente acrescenta suas funcionalidades. Não se deve interpretar o delta como custo de um programa idêntico.

A cada snapshot o modelo constrói o mesmo payload público/ACK privado da implementação em teste e mede `var_to_bytes`. Snapshot antigo contém tick/session/players/ack; novo acrescenta ambiente, sons e inspeção privada vazia. A versão inicial repete a montagem pública por destinatário, como fazia a produção em `4abbe51`. Os **bytes são estimativa de Variant**, sem framing RPC/WebSocket/TCP, compressão, retransmissão TCP, handshake ou outros eventos. A projeção de bytes/s usa exatamente 20 Hz e N destinatários, não bytes observados no fio.

| Participantes/carga | Baseline média por tick (µs) | Fase 2 antes de otimizar (µs) | Snapshot baseline por destinatário (bytes) | Fase 2 antes (bytes) | Fase 2 antes, todos destinatários (bytes/s estimados) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 4 / static | 118.16 | 246.06 | 988.00 | 4716.00 | 377280 |
| 4 / active | 132.40 | 435.11 | 988.00 | 9164.62 | 733170 |
| 8 / static | 245.56 | 450.72 | 1772.00 | 5500.00 | 880000 |
| 8 / active | 280.90 | 790.41 | 1772.00 | 9978.07 | 1596491 |

Tempo é **wall elapsed de um modelo limitado por CPU**, incluindo validação/filas, física determinística, regras, cópias e serialização. Não é utilização percentual da CPU, tempo de física nativa isolado nem latência remota. Percentis e máximos completos ficam no JSON. Antes de otimizar, caso oito ativo: p95 **1731 µs** por tick; a margem em relação ao tick de 16.667 ms neste modelo não garante a mesma margem em produção/Web.

Estado é limitado: **23 objetos**, ring de **32 sons**, sem crescimento de objetos Godot durante os 1200 ticks medidos em nenhum caso. Processo passou de 1451 objetos na baseline para 1460 na Fase 2. Memória estática de processo aproximadamente 21.1→21.6 MB; delta dentro de cada caso de 32–39 KB inclui o vetor de 1200 amostras. Esses contadores não são RSS total nem memória de GPU. Inspeção não vazia tem tamanho adicional; o modelo usa ausência de inspeção para comparar o caso comum.

A medição detectou custo relevante: ring de sons e 23 DTOs completos repetidos em cada snapshot levavam o caso oito ativo a **~1.60 MB/s de Variant estimado**. Mesmo limitado, esse custo justifica compactar a representação no transporte e reaproveitar uma cópia pública por sala, preservando os DTOs e a autoridade. O valor inicial permanece registrado, sem ser substituído pela medição posterior.

## Otimização guiada pela medição

O transporte passou a codificar geometria estática por catálogo distribuído com o build: bitmask dos vinte estados de porta e três estados de props; sons usam round/id inicial e linhas tipo/posição/peer sem repetir chaves. A cópia pública e sua codificação são feitas **uma vez por sala/snapshot**, fora do loop de destinatários. ACK e inspeção continuam privados por peer. DTOs públicos, limites de eventos e semântica de autoridade permanecem intactos. Esta representação pertence ao protocolo 12 explicitamente documentado; não se afirma compatibilidade com clientes de protocolo 11.

O mesmo modelo foi adaptado para detectar `encode_wire` dinamicamente e usar o caminho efetivo de produção: `EnvironmentRules.encode_wire(snapshot)` / `SoundEventRules.encode_wire(events)` hoistados. Os resultados anteriores foram preservados; esta nova execução está em `runtime.optimized` do JSON. A identidade inclui HEAD mais fingerprint exato dos fontes, pois o codec ainda estava no worktree aguardando commit durante a medição. Não se repetiu render após o codec: a apresentação recebe os mesmos DTOs reconstruídos, e a mudança não afeta seus métodos ou shaders.

| Participantes/carga | Média após (µs/tick) | p95 após (µs/tick) | Snapshot antes→após (bytes/destinatário) | Redução de payload | Todos destinatários após (bytes/s estimados) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 4 / static | 213.07 | 420 | 4716.00 → 1244.00 | 73.6% | 99520 |
| 4 / active | 368.79 | 706 | 9164.62 → 2540.20 | 72.3% | 203216 |
| 8 / static | 352.78 | 647 | 5500.00 → 2028.00 | 63.1% | 324480 |
| 8 / active | 623.58 | 1183 | 9978.07 → 3332.00 | 66.6% | 533120 |

Caso oito ativo: **9978.07→3332 bytes por destinatário**, redução de **66.6%**; projeção de 1.60 MB/s para **0.533 MB/s** no conjunto dos oito peers. Ainda excede a baseline sem os recursos novos (0.284 MB/s). Não é tráfego TCP observado nem promessa de largura de banda remota; eventos/round_state e framing não estão incluídos. A ring de 32 eventos permanece para bootstrap/deduplicação, sem fila extra por destinatário.

Modelo oito ativo: média **790.41→623.58 µs/tick**, p95 **1183 µs**, máximo **2652 µs** após. Há redução observada da montagem/serialização, mas continua mais caro que a baseline sem os recursos. Tamanho de payload é determinístico para a carga; os deltas de tempo são uma execução de wall time em host compartilhado, sem inferir ganho percentual garantido.

Custo novo no cliente medido separadamente, fora dos tempos acima: **1000 reconstruções consecutivas** de `decode_wire` para os 23 objetos e ring de 32 sons, média **291.218 µs** no caso quatro ativo e **296.465 µs** no caso oito ativo; com ring vazio, **144.529/144.300 µs**. Resultados reconstruíram exatamente 23 objetos e 32/0 eventos. É microbenchmark de decode no mesmo host, sem áudio/render/sanitização adicional do consumidor, não tempo de frame total. Eventos continuam limitados; vozes continuam 12; todos os comandos e seis interações continuaram aceitos.

## Cena gráfica carregada

X11 :99, Compatibility/Mesa llvmpipe LLVM 19, **renderização por software**, 960×540, 120 quadros de aquecimento e 300 amostras por execução. A cena comum tem oito avatares remotos, um corpo, mapa oficial, movimento visual/interpolação e 14 efeitos de disparo. Na Fase 2 ela também recebe os 23 objetos, inspeção visível, 14 DTOs sintéticos de som no formato público de recarga/manuseio e seu pool fixo de 12 vozes; eventos acionam poses remotas. O cenário injeta DTOs públicos como fixture de apresentação, não comprova a ocorrência de uma partida real.

A cada quadro verifica snapshot oficial do mundo e origem/direção da câmera: **zero mutações em todas as seis execuções verdes**. Meshes/luzes do mapa permanecem **248/24**. Nodes recursivos da view: **707→746**; contagem de objetos do processo no perfil padrão: **2565→2704**; memória estática aproximada **46.64→47.99 MB**, não VRAM.

| Fonte/perfil | p50 (ms) | p95 (ms) | p99 (ms) | Máximo (ms) |
| --- | ---: | ---: | ---: | ---: |
| baseline-baseline | 24.424 | 29.138 | 36.205 | 36.694 |
| current-baseline | 26.311 | 40.428 | 54.810 | 217.317 |
| baseline-baseline-repeat | 22.919 | 31.247 | 35.494 | 37.847 |
| current-baseline-repeat | 23.956 | 32.675 | 37.298 | 52.999 |
| baseline-low | 17.133 | 24.266 | 27.554 | 38.852 |
| current-low | 16.758 | 20.083 | 27.848 | 31.951 |

A primeira comparação apresentou outlier de 217 ms na Fase 2. Por essa variância, foi feita **uma repetição fixa do par padrão**, preservando ambos os pares; não se escolheu o melhor resultado. O p95 padrão variou 29.138–31.247 ms na baseline e 32.675–40.428 ms na Fase 2. Há custo e variância, não ganho comprovado. Low custou menos neste host, mas uma amostra em que o novo ficou mais rápido que o antigo não estabelece otimização causada pela Fase 2. As imagens baseline e nova foram inspecionadas: cenário/personagens e texto de inspeção legíveis no driver usado. Não é validação humana de conforto, justiça visual ou hardware.

A execução inicial da fixture gráfica media corretamente, mas liberava a view antes de dois timers cosméticos finais: surgiram erros de lambda no cleanup. Foi mantida como **RED**, fora das seis execuções verdes; o benchmark passou a aguardar 0.5 s antes de liberar o dono dos timers. Todos os seis runs finais saíram 0, sem ERROR/Parse/SCRIPT/ObjectDB. Nenhum processo Godot próprio restou após a sessão; display preexistente preservado. Não houve alteração de runtime para corrigir a fixture.

## Reprodução

```sh
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
"$GODOT_BIN" --headless --path . --script tests/phase2_runtime_benchmark.gd
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 "$GODOT_BIN" --path . \
  --audio-driver Dummy --rendering-method gl_compatibility --rendering-driver opengl3 \
  tests/scenes/phase2_graphics_benchmark.tscn -- --profile=baseline --screenshot=/tmp/phase2-loaded.png
# Mesmo comando --profile=low para o perfil conservador.
```

Para repetir a comparação antiga, copie os dois scripts/cena de benchmark para um arquivo limpo de `59926cb` depois da importação gráfica completa descrita em [baseline.md](baseline.md). Os scripts detectam componentes novos em runtime; o arquivo antigo não ganha implementações de gameplay por esse processo. Nenhum projeto externo, plugin físico ou asset foi instalado para estas medições.

## Compatibilidade e limites

Windows/Web/container e transporte real quatro/oito dependem das evidências finais de CI e dos harnesses multiprocesso, não destes números de modelo. Não foram certificados Android, macOS, GPU física ou rede remota. A simulação ambiental é o integrador determinístico do projeto; não se declara comparação de runtime nativo Jolt sem extensão compatível efetivamente executada. Tempo de física nativa, CPU percentual e RSS detalhado não medidos. Bytes de eventos de combate/room_state fora do snapshot não entram na estimativa.

## Regressões após a compactação e cleanup de testes

`environment_wire_test.gd`: RED codec ausente → **23checks GREEN**, roundtrip exato de ambiente/sons, bitmask, limites de tamanho, tipos, valores não finitos e sequência contígua. Suíte completa posterior **44/44 PASS**. Novo harness real4RTT200 passou também após a compactação, sem erros de engine e com shutdown completo; a matriz final repete a revisão final.

A investigação do novo harness também confirmou ciclo de referências preexistente no helper de atraso de testes: inner→lambda→wrapper→inner. Uma factory estática com WeakRef preserva encaminhamento enquanto vivo e permite liberar wrapper/inner; não muda perfis, filas, seeds ou tempos. Novo lifecycle42checks RED→GREEN, netcode266 e harness legado RTT200 PASS; logs da execução positiva ficaram sem ObjectDB/resourceERROR. A sonda negativa de protocolo continua produzindo a recusa esperada, não é vazamento ou regressão. Apenas infraestrutura de teste foi alterada. Evidência detalhada em evidence/net-delay-cleanup.md.
