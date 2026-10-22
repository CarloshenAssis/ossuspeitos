# SPEC 07 — instrumentação limitada da rede existente

Base de integração: `9d158bf`; Godot 4.4.1, WebSocket/TCP, protocolo 11,
60 ticks/s e snapshots a 20 Hz preservados. Não há alteração de RPC, input,
snapshot público, ACK privado, gameplay ou buffers de prediction/interpolação.

`AuthoritativeWorld` agora oferece `set_telemetry_enabled(bool)` e
`telemetry_snapshot()`: estatísticas locais por mundo/sala, nunca RPCs. O
`NetworkApp` reaproveita `--net-stats=<intervalo_ms>` no servidor local de
desenvolvimento para imprimir `SERVER_NET_STATS`. Desligado por padrão; o
servidor dedicado continua com a allowlist estrita existente e não ganha flag
de release. Não use flags de teste em produção.

A medição serializa somente após `NetSync.parse_packet` validar tipos, formas,
tamanho do lote e ação (inclusive string de pickup limitada). Conta pacotes
estruturalmente válidos, bytes estimados por `var_to_bytes`, comandos enfileirados,
duplicatas e maior profundidade observada. Um pacote válido pode depois ser
recusado por sequência, época ou regras: esses bytes não significam comandos
executados. Pacotes barrados pelo rate limit não são medidos. Não estima o
tráfego total recebido, snapshots ou framing RPC/WebSocket/TCP/TLS.

As 128 amostras contêm apenas tamanhos inteiros; contadores saturam em
2.147.483.647. Recusas usam categorias fixas, incluindo `other`, impedindo
crescimento por motivos arbitrários dos callbacks. `clear()` limpa estado e
medidas; alternar instrumentação limpa medidas opcionais, preservando estado
e recusas. Remover/reconectar peer limpa sua fila e ACK, mantendo agregados da
sala até reset explícito. Consultas retornam cópias profundas. Não armazena
labels, papéis, inventários ou conteúdo dos comandos. Desligado não chama
`var_to_bytes`; o custo restante é uma condição por observação.

## Comparação conceitual

Referência fixada no [registro de licenças](license-register.md): ioquake3
`87a99d18206e878a20289f05ac3c16005dcae5c3`, arquivos
`code/client/cl_parse.c`, `code/client/cl_input.c`,
`code/server/sv_snapshot.c` e `code/server/sv_client.c`.
Somente análise conceitual independente; nenhum código GPL incorporado.

A separação entre comandos, sequência/ACK, snapshots e validação de mensagens
antigas já existe em `NetSync`, `AuthoritativeWorld`, `PlayerPrediction` e
`RemoteInterpolator`. A melhoria aqui torna visíveis duplicatas e pressão da
fila sem reconstruir esses sistemas. Os limites atuais continuam: 8 comandos
por pacote, fila 32, orçamento 12, no máximo 4 comandos simulados por tick.
Eventos reliable e snapshots não criam canais fisicamente independentes no
TCP: um atraso de transporte pode bloquear ambos. Nenhuma conclusão sobre
perda UDP, delta compression, rewind ou migração ENet é feita.

## Evidência e reprodução

Fonte o ambiente homologado antes de cada execução: `source
/workspace/.ossuspeitos-state/mission-sdd/env.sh`. Execute `$GODOT_BIN --headless
--path . --script tests/network_telemetry_test.gd` e
`tests/network_telemetry_benchmark.gd`. Logs completos ficam fora do repositório
em `/workspace/.ossuspeitos-state/mission-sdd/spec07/`.

Benchmark em processo, quatro peers, 2.400 ticks (40 s simulados), comandos
parados, mesmo input off/on, sem renderização nem transporte. Uma execução
neste ambiente compartilhado:

| lote | off µs | on µs | diferença | bytes Variant/pacote | bytes estimados/s/peer |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2 (cadência normal) | 157185 | 168776 | +7,4% | 128 | 3840 |
| 8 (rajada) | 140176 | 148893 | +6,2% | 416 | 3120 |

Diferença absoluta de aproximadamente 1,21/0,91 µs por peer/tick; amostra única,
sem claim de benchmark estável ou ganho de throughput. Maior fila observada
2/8. A instrumentação não é otimização de payload nem medição de bandwidth
TCP. O teste de inundação observa fila 32, duplicata sem execução e descarte
por época, além de limite de amostras, saturação, rate limit, ação grande,
isolamento de peer/sala, cópias e reset; DTOs públicos/ACK são comparados pelas
chaves exatas.

Verificação: `NETWORK_TELEMETRY_TEST_OK`; netcode 266 asserts, round authority
192, rooms 2626 e shutdown handshake 47. Multiprocesso: sync local e rtt200
(4 clientes + build incompatível), round network (4 participantes + entrada
tardia), rooms network, rooms adversarial, rooms resilience e combat4 passaram.
Um wrapper externo apenas acrescentou `--net-stats=1000` ao servidor dos testes
de combate estendido com 4/8 clientes, sem modificar o harness ou as flags
permitidas de produção. Na execução de 4 clientes, 10 resumos periódicos;
última observação: 498 pacotes validados, 64.376 bytes Variant estimados,
993 comandos enfileirados, 2 duplicatas, fila máxima 5 e 128 amostras. São
observações até o último intervalo, não total de sessão ou taxa de fio TCP.

Combate estendido de 8 clientes também passou: 26 resumos; última
observação 1013 pacotes, 130576 bytes estimados, 2023 comandos,
0 duplicatas, fila máxima 4, 128 amostras. O teste conserva
asserções de privacidade, reset de rodada, espectador e shutdown completo.
