# Armed Mystery

Protótipo Godot 4 com servidor headless autoritativo e clientes locais conectados
por WebSocket. O segundo marco adicionou uma arena 3D provisória, movimento em
primeira pessoa e cápsulas interpoladas para os jogadores remotos. O marco atual liga o primeiro combate jogável às fundações autoritativas:
uma pistola comum, pickups fixos, vida, munição, recarga, hitscan bloqueado por
paredes e eliminação.

## Requisitos

- Godot 4.4 ou mais recente (`godot4` ou `godot` no `PATH`).
- Bash para executar o teste de integração.

## Execução local

Inicie o servidor (por padrão, somente em `127.0.0.1:9080`):

```bash
godot4 --headless --path . -- --mode=server
```

Em quatro terminais, varie o identificador do cliente:

```bash
godot4 --headless --path . -- --mode=client --client-id=client-1
```

O endereço pode ser alterado com `--url=ws://host:porta`. O servidor aceita
`--bind=endereço`, `--port=porta` e também a variável de ambiente `PORT`.
Nos clientes gráficos, use WASD para mover e o mouse para girar a câmera. O
cliente envia apenas eixos de entrada e variação de rotação; posição e velocidade
são calculadas, limitadas e publicadas pelo servidor. Durante uma rodada ativa,
use **E** para coletar, clique esquerdo para atirar e **R** para recarregar.
Quando eliminado oficialmente, o cliente para de enviar gameplay e **Q/E**
alternam localmente entre jogadores vivos autorizados pelo servidor.

## Ciclo de partida

O servidor é a única autoridade sobre participantes, fase da rodada, contagem
regressiva, sorteio de papéis, estado vivo/morto, vencedor e reinício. O cliente
envia apenas intenções e recebe o resultado oficial.

### Estados da rodada

| Estado | Significado | Transições válidas |
| --- | --- | --- |
| `WAITING` | Lobby aberto, sem papéis e sem vencedor | `COUNTDOWN` |
| `COUNTDOWN` | Contagem publicada pelo servidor | `ACTIVE`, `WAITING` |
| `ACTIVE` | Participantes congelados, papéis sorteados | `ENDED` |
| `ENDED` | Vencedor registrado, gameplay bloqueado | `WAITING`, `COUNTDOWN` |

Qualquer outra transição é recusada e registrada como
`ROUND_TRANSITION_REJECTED`. Todo prazo usa o tempo do servidor e carrega o
identificador da rodada que o criou, portanto um temporizador antigo nunca
altera a rodada seguinte.

### Quantidade de jogadores e distribuição dos papéis

São aceitos de 4 a 8 jogadores (`RoundRules.MIN_PLAYERS` e
`RoundRules.MAX_PLAYERS`); o nono é recusado com `room_unavailable`. Toda rodada
válida tem exatamente **1 assassino**, **1 detetive** e o restante **vítimas**:
2 vítimas com 4 jogadores, 6 vítimas com 8.

O sorteio acontece somente no servidor, usa um `RandomNumberGenerator` injetável
(`--round-seed=` para reproduzir), embaralha por Fisher-Yates e portanto não
favorece a ordem de conexão. Cada rodada produz uma distribuição nova.

### Limite de sigilo

O mapa completo de papéis existe apenas em `RoundAuthority` e nunca sai por
broadcast. Cada cliente recebe o próprio papel por `rpc_id`, depois que o
servidor confirma que o peer pertence à rodada, que a rodada está `ACTIVE` e que
o papel é dele. Roster público, snapshots de movimento, estado público, logs de
cliente e a demo offline não têm campo de papel. Os logs de servidor só trazem a
contagem agregada (`ROUND_ROLE_COUNTS assassin=1 detective=1 victim=2`), nunca a
associação entre peer e papel. Não existe RPC que permita ao cliente escolher o
próprio papel, consultar o papel alheio ou declarar morte; o servidor também
desliga o relay do `SceneMultiplayer`, então um cliente não consegue endereçar
RPC a outro cliente.

### Join tardio

Quem entra durante `WAITING` ou `COUNTDOWN` participa da rodada. Quem entra com
a rodada `ACTIVE` ou `ENDED` fica só no lobby, não recebe papel, não pode ser
eliminado e aguarda o próximo `WAITING` (marcador `ROUND_LATE_JOIN`).

### Política de desconexão

| Fase | Efeito |
| --- | --- |
| `WAITING` | Apenas atualiza o lobby |
| `COUNTDOWN` | Cancela a contagem e volta a `WAITING` se restarem menos de 4 |
| `ACTIVE`, participante vivo | Conta como eliminado (`cause=disconnect`) e reavalia a vitória |
| `ACTIVE`, assassino | Vitória imediata dos inocentes |
| `ACTIVE`, último inocente | Vitória do assassino |
| `ACTIVE`, detetive | Conta como eliminado, mas não encerra se houver vítima viva |
| `ENDED` | Apenas remove a sessão |

Durante a rodada nada anuncia que o jogador desconectado era o assassino: só o
estado de vida muda. O papel aparece no máximo como parte do resultado final.

### Condições de vitória

- **Inocentes** vencem quando o assassino não está mais vivo
  (`reason=assassin_down`).
- **Assassino** vence quando está vivo e não resta nenhum inocente vivo
  (`reason=innocents_down`).

Neste marco, "inocente" é `DETECTIVE` ou `VICTIM`. A avaliação roda no servidor
após cada eliminação e após cada desconexão durante `ACTIVE`. O resultado público
tem somente identificador da rodada, equipe vencedora (`ASSASSIN` ou
`INNOCENTS`) e a razão sanitizada.

### Eliminação

`RoundAuthority.eliminate_player(peer_id, cause, instigator_peer_id, now_msec)` é
API interna do servidor, sem RPC equivalente. Ela recusa peer inexistente,
jogador fora da rodada, eliminação duplicada e rodada que não esteja `ACTIVE`, e
sanitiza a causa antes de registrar. Por enquanto só os testes e o gancho de
teste do servidor a chamam; o sistema de combate futuro usará o mesmo ponto.

### HUD provisório

O cliente gráfico carrega `client/round_hud.tscn` e mostra estado da rodada,
jogadores conectados, contagem regressiva, papel local depois do início, estado
local vivo/morto, vencedor e o aviso de quem aguarda a próxima rodada. O HUD não
calcula papel, vitória nem vida: ele só formata o que o servidor publicou. O
servidor headless nunca carrega essa cena — os marcadores
`SERVER_UI hud=false arena=false display=headless` e `CLIENT_UI ...` são
derivados do estado real dos nós e verificados pelos testes.

### Espectador básico e revelação final

Ao eliminar um participante, o servidor bloqueia movimento, pickup, tiro e
recarga e envia **somente a ele** a lista dos participantes vivos, conectados e
pertencentes à rodada. A seleção Q/E é puramente local e a câmera segue posição
e yaw oficiais dos snapshots; não há RPC de seleção arbitrária, câmera livre,
controle do alvo, killcam, respawn ou chat de mortos. Sem alvo, o HUD mostra
`Aguardando fim da rodada`.

Papéis alheios seguem ausentes em `WAITING`, `COUNTDOWN` e `ACTIVE`. Somente
depois da transição oficial para `ENDED`, cada participante conectado recebe uma
allowlist com `round_id`, equipe vencedora, razão e participantes/papéis finais.
Vida, inventário, munição e seed nunca integram esse resultado. O reset limpa a
revelação e o mapa de papéis antes da rodada seguinte.

## Testes

```bash
# regras puras da rodada
godot4 --headless --path . --script tests/round_rules_test.gd
# apresentação do HUD, sem renderização
godot4 --headless --path . --script tests/round_hud_test.gd
# autoridade headless: estados, papéis, vivo/morto, vitória, reinício
godot4 --headless --path . --script tests/round_authority_test.gd
# regras de movimento
godot4 --headless --path . --script tests/movement_rules_test.gd
# arma, inventário, validação de tiro e combate integrado
godot4 --headless --path . --script tests/weapon_rules_test.gd
godot4 --headless --path . --script tests/inventory_authority_test.gd
godot4 --headless --path . --script tests/combat_rules_test.gd
godot4 --headless --path . --script tests/combat_authority_test.gd
# espectador privado, revelação final e apresentação
godot4 --headless --path . --script tests/spectator_reveal_authority_test.gd
godot4 --headless --path . --script tests/spectator_reveal_client_test.gd
./tests/spectator_reveal_network_test.sh
# sigilo dos papéis com servidor e cinco clientes reais
./tests/round_network_test.sh
# auditoria adversarial: peer hostil contra uma rodada real
./tests/round_adversarial_test.sh
# regressão de movimento com servidor e quatro clientes reais
./tests/network_smoke_test.sh
```

O teste de movimento abre uma porta local aleatória, inicia cinco processos
headless, exige quatro sessões simultâneas com IDs de peer distintos e encerra
todos os processos. O teste de sigilo sobe um servidor, quatro clientes que
participam da rodada e um quinto que chega tarde; ele confirma que cada cliente
recebe exatamente um papel, que nenhum log traz papel alheio e que a tentativa de
um cliente entregar papel a outro não chega ao destino. Se o executável não
estiver no `PATH`, use `GODOT_BIN=/caminho/para/godot ./tests/...`.

O teste adversarial sobe uma rodada legítima de quatro participantes e injeta um
quinto peer hostil que chega depois do início: ele envia tipos errados, rótulos
gigantes, `round_id` forjado, RPC antes do handshake, RPC de autoridade e spam de
confirmação. As asserções exigem que o servidor sobreviva, continue autoritativo e
que esse peer nunca receba papel algum.

Argumentos úteis do servidor: `--countdown-seconds=`, `--round-end-delay-seconds=`
e `--round-seed=` para rodadas curtas e reproduzíveis. Sem `--round-seed`, o
sorteio usa `RandomNumberGenerator.randomize()`: a seed nunca vem do cliente.

## Limitações deste marco

Ainda **não existem**: lojas, créditos, armas especiais, ressurreição, corpos,
espectador com câmera livre, voz, chat, matchmaking, Railway, Android ou arte definitiva.
O hitscan atual usa geometria analítica simples, sem headshot, previsão ou lag compensation.

## Demonstração visual offline

A demonstração é um modo de apresentação isolado, claramente marcado como
**OFFLINE / SEM SERVIDOR**. Ela permite andar pela arena com WASD, capturar o
mouse com um clique, liberar com Esc e observar quatro cápsulas simuladas:

```bash
godot4 --path . -- --mode=demo
```

Esse modo não cria transporte, não conecta a um servidor, não instancia a
autoridade de movimento e não é acionado como fallback de falhas multiplayer. O
cliente real continua enviando apenas comandos de entrada ao servidor. A demo
continua mostrando somente **OFFLINE / SEM SERVIDOR** e nunca simula papéis,
eliminação autoritativa, espectador ou revelação final.

## Build Web como artifact

Em **Actions → Godot Web demo build**, selecione **Run workflow**. O job instala
Godot 4.4.1 e os templates oficiais, valida o projeto e a demo, exporta o preset
`Web Demo` e publica o artifact `armed-mystery-web-demo`.

Pull requests executam todas as validações e geram o artifact para inspeção, mas
nunca publicam o site. A publicação no environment `github-pages` ocorre somente
em uma execução manual ou após push na branch `main`, e apenas se parser, testes
determinísticos, teste multiplayer, exportação e verificações passarem.

Baixe e extraia o artifact. Sirva a pasta extraída por HTTP — não abra
`index.html` diretamente com `file://`:

```bash
python3 -m http.server 8000 --directory caminho/para/armed-mystery-web-demo
```

Abra `http://localhost:8000/`, clique na arena para capturar o mouse e use WASD.
O preset não usa threads Web, portanto essa visualização local não exige os
headers COOP/COEP. A validação visual final deve confirmar o banner offline, a
arena, a câmera em primeira pessoa e quatro cápsulas coloridas em movimento.
