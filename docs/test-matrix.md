# Matriz de testes da fase 5

Fonte de verdade: o servidor autoritativo, salvo quando a linha diz
"cliente" (o que o cliente realmente recebeu, relatado por RPC de teste).
Todo harness grava um log por processo em `TEST_LOG_DIR` (com seed e SHA no
`run=`), imprime `HARNESS_STAGE` por etapa e, na falha, o fim de cada log.
O watchdog é só uma salvaguarda: se disparar, o teste falha.

## Cenário principal — `tests/campaign_test.sh`

8 clientes, 3 rodadas, uma sessão. `PROFILE=local|rtt150j SEED=n`.
Tempo limite: 30 s por passo e 420 s no total (watchdog).

| ID | Requisito | Setup | Ação | Resultado esperado | Fonte de verdade |
| --- | --- | --- | --- | --- | --- |
| C1 | Entrada | 8 clientes | Conectar | 8 participantes; aparência de cada um mantida nas 3 rodadas | servidor |
| C2 | Navegação | Ator na porta leste do Salão, outro jogador no corredor | Roteiro de comandos | Passa pela porta e pelo corredor em L; nunca dentro da geometria; previsão = oficial | servidor + cliente |
| C3 | Coleta | Ator sobre `weapon_1` e `ammo_1` | Ação de coleta | Aceita; item indisponível | servidor |
| C4 | Acerto, erro, obstrução | Faixa de tiro de 3 m; parede entre atirador e alvo | Tiros reais | Vida 100→66; erro sem dano e com munição gasta; parede para o tiro | servidor |
| C5 | Eliminação e espectador | Segundo e terceiro tiro | Tiros reais | Alvo eliminado; alvos do espectador = conjunto calculado à parte | servidor + cliente |
| C6 | Ações de morto | Espectador | Coleta, tiro, recarga | Todas recusadas com `player_dead` | servidor |
| C7 | Fim da rodada | Rodadas 1, 2, 3 | Regras existentes | `assassin_down`, `innocents_down`, `assassin_down` | servidor |
| C8 | Reveal | ENDED | — | 8 clientes recebem o reveal só em ENDED, com os papéis certos, uma vez por rodada | cliente |
| C9 | Reset | Início das rodadas 2 e 3 | — | Vida 100, sem arma, 8 itens disponíveis, sem espectador/reveal, época nova | servidor |
| C10 | Callbacks antigos | Início das rodadas 2 e 3 | Comando de época velha, alvos e reveal com `round_id` antigo | Comando recusado com `stale_epoch`; cliente ignora o resto | servidor + cliente |
| C11 | Recursos | Baseline após a rodada 1 | 3 rodadas | Coleções oficiais = 8; objetos ±2%; filas limitadas | servidor + cliente |
| C12 | Saída | Fim | Encerramento coordenado | Todos saem com 0; nenhum órfão; porta livre; sessão de controle na mesma porta | harness |

Artefatos de falha: `server.log`, `client-N.log`, `control/`.

## Casos adversos — `tests/adverse_cases_test.sh`

Status esperado por processo: 0, 1 (recusa prevista) ou 137 (kill -9 do
harness). Tempo limite: 30 s por passo, 240 s por caso e 900 s no total.

| ID | Caso | Setup | Ação | Resultado esperado | Fonte de verdade |
| --- | --- | --- | --- | --- | --- |
| A1 | `menu_errors` | Menu sem servidor | Endereço inválido; porta sem servidor | Mensagem em português; volta ao menu; 1 tentativa só | cliente |
| A2 | `busy_port` | Porta ocupada por outro processo | Servidor e "Criar partida" nela | `SERVER_ERROR unable_to_listen` e `port_in_use`; o ocupante continua vivo e respondendo | harness |
| A3 | `version_and_crash` (1) | Servidor | Cliente com protocolo 8 | Recusa `protocol_version`; status 1 | servidor + cliente |
| A4 | `ninth` | 8 em ACTIVE | Nono cliente | Recusa `room_unavailable`; sala inalterada e jogável | servidor |
| A5 | `double_click` | Menu | Dois cliques em Entrar/Criar no mesmo quadro | 1 conexão; 1 servidor | cliente + servidor |
| A5b | `join_ended` (1) | 4 em ACTIVE | Mesmo nome de um jogador conectado | Recusa; sessão original intacta | servidor |
| A6 | `join_ended` (2) | ACTIVE e depois ENDED | Novo cliente em cada estado | Espera sem papel; os dois jogam a rodada seguinte com papel próprio | servidor + cliente |
| A7 | `drop_moving` | Jogador andando (4,5 m/s) | kill -9 | Estado removido; rodada segue; os outros continuam recebendo snapshots | servidor + cliente |
| A8 | `observed_leaves` | Espectador observando T | kill -9 em T | Alvos atualizados; câmera sai de T para um alvo permitido | cliente |
| A9 | `version_and_crash` (2) | 2 jogadores pelo menu | kill -9 no servidor | Os dois voltam ao menu com mensagem, sem nova tentativa; porta livre | cliente |
| A10 | `leave_rejoin` | Jogador com arma | kill -9 e volta com o mesmo nome | Peer novo, época 1, sem vida/inventário herdados; joga a rodada seguinte | servidor + cliente |
| A11 | `invalid_actions` | Vivo sem arma; morto | Ações inválidas e 15 payloads malformados | Recusas com o motivo da própria regra; estado oficial inalterado; sem vazamento | servidor |
| A12 | `phase4_delay` | 150 ms com jitter | Eliminação com tiros pendentes; reinício com comandos em trânsito | Sem tiro póstumo; recusas `player_dead`/`stale_epoch`/`round_not_active`; previsão nova = oficial | servidor + cliente |

Artefatos de falha: `<caso>/server.log`, `<caso>/<cliente>.log`.

## Sessão gráfica — `tests/campaign_visual_session.sh` (fora do CI)

Ator e observador gráficos (xvfb, OpenGL) e 6 automatizados. Cenas: navegação
(ator e observador), coleta, mira vertical (ator e cabeça vista pelo
observador), acerto, obstrução, eliminação, espectador seguindo o ator,
reveal e nova rodada. Saída: quadros JPG, CSV por quadro, prancha PNG e WebM
por cena.

## Fase 6 — reset, pickups e corpos

| ID | Requisito | Onde | Resultado esperado | Fonte de verdade |
| --- | --- | --- | --- | --- |
| R1 | Sobrevivente e eliminado voltam ao spawn | `round_reset_bodies_test`, campanha (rodadas 2 e 3) | Posição = spawn oficial, yaw do spawn, pitch 0, parado, 8 spawns distintos | servidor + cliente (previsão) |
| R2 | Comandos antigos | `round_reset_bodies_test` | Recusados com `stale_epoch`, sem mover | servidor |
| R3 | Teleporte no cliente | `round_reset_bodies_test` | Previsão sem pendentes nem offset; remoto nunca entre a posição velha e o spawn | cliente |
| P1 | 8 pistolas e 12 munições | `arena_layout_test`, `combat_authority_test`, campanha | Contagem exata; posições oficiais válidas e alcançáveis | servidor |
| P2 | Distribuição | `arena_layout_test` | 8 áreas de arma; munição em ≥ 9 áreas; oeste, núcleo e leste; distâncias de spawns, portas e entre pickups | mapa |
| P3 | Coleta única e restauração | `round_reset_bodies_test`, campanha | 20 disponíveis a cada rodada; segundo pedido `item_unavailable`; sem crescimento em 3 rodadas | servidor + cliente |
| P4 | Oito jogadores, oito armas | `arena_layout_test` | Cada um coleta uma pistola diferente e não alcança outra | servidor |
| B1 | Corpo só por eliminação oficial | `round_reset_bodies_test`, adverso `observed_leaves` | Sair vivo não gera corpo | servidor |
| B2 | Duplicata e callback antigo | `round_reset_bodies_test`, campanha | Um corpo por jogador por rodada; corpo de rodada anterior ignorado | servidor + cliente |
| B3 | DTO público | `round_reset_bodies_test`, campanha | Allowlist exata, sem papel, inventário ou munição | cliente |
| B4 | Mesmos corpos em todos os clientes | campanha | 2 corpos em pontos diferentes (Salão e Ala leste) na rodada 1; igualdade em todas as rodadas | servidor + 8 clientes |
| B5 | Sem colisão nem raycast | `round_reset_bodies_test` | Tiro passa pelo corpo e acerta o vivo atrás; ponto continua livre | servidor |
| B6 | Corpo após desconexão do eliminado | adverso `observed_leaves` | Corpo permanece para todos | servidor + clientes |
| B7 | Remoção no reset | `round_reset_bodies_test`, campanha | 0 corpos no início das rodadas 2 e 3 | servidor + cliente |
| B8 | Apresentação | `round_reset_bodies_test`, sessão gráfica | Deitado no piso (altura < 0,75 m), aparência preservada, parado; correção junto à parede ≤ 0,6 m | cliente |
