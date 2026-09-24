# Decisões do protótipo

## Transporte inicial

O primeiro deploy remoto terá como alvo Railway usando WebSocket/TCP. A lógica da partida não dependerá do transporte, permitindo migrar para ENet/UDP em VPS quando latência, hospedagem ou escala justificarem.

## Autoridade

O servidor resolve todas as ações que afetam regras ou resultados. O cliente controla apresentação, entrada e previsão visual quando implementada.

## Marco 1: processo e sessão de rede

Um único projeto Godot seleciona servidor ou cliente por argumentos após `--`,
mas instancia apenas o comportamento pedido. O transporte usa
`WebSocketMultiplayerPeer`; configuração compartilhada fica em `shared/`, enquanto
o servidor mantém o mapa oficial de `peer_id` para sessão. O identificador enviado
pelo cliente é metadado não confiável: a identidade de rede sempre vem de
`multiplayer.get_remote_sender_id()`.

O servidor escuta loopback por padrão para desenvolvimento seguro e aceita bind e
porta configuráveis, inclusive `PORT` para futura hospedagem. Nenhuma API do
Railway integra a sessão. Gameplay futuro continuará separado do transporte para
permitir trocar WebSocket/TCP por ENet/UDP.

O teste do marco executa um servidor e quatro clientes como processos headless
independentes. Marcadores de log, timeout e códigos de saída verificam que quatro
clientes estiveram conectados simultaneamente antes do encerramento controlado.
O encerramento é coordenado pelo servidor: cada cliente confirma sua conclusão,
o servidor valida quatro `peer_id` distintos, entra em estado de shutdown antes
de autorizar as saídas e termina após as desconexões ou um timeout curto.

## Marco 2: movimento autoritativo

O cliente transmite apenas uma sequência, um eixo de movimento e uma variação de
rotação limitada. O servidor deriva o jogador do remetente da RPC, rejeita valores
não finitos, magnitudes impossíveis e sequências antigas, e calcula posição,
velocidade e rotação usando seu próprio passo de física. O estado oficial é
limitado à arena e publicado em snapshots; clientes apenas interpolam cápsulas
remotas e posicionam a câmera local a partir desses snapshots.

A autoridade de movimento não instancia geometria. Os oito spawns e limites ficam
em regras compartilhadas determinísticas, enquanto piso, paredes, iluminação,
câmera e cápsulas pertencem somente à apresentação do cliente. O transporte
WebSocket permanece independente.

O encerramento usa duas fases para não disputar com sockets em fechamento. O
servidor primeiro interrompe snapshots, roster e comandos, envia uma única
preparação e espera uma confirmação deduplicada de cada peer. Somente então o
servidor fecha o `MultiplayerPeer`; clientes permanecem conectados até observarem
essa desconexão esperada e nenhuma RPC é enviada após o início do fechamento. O
fechamento local é terminal: o servidor cancela o timeout de preparação, preserva
a contagem encerrada, limpa explicitamente suas tabelas autoritativas e termina
sem depender de callbacks de desconexão que o peer já fechado não produzirá.

## Marco visual: demo e exportação Web

O artifact Web usa a feature de exportação `visual_demo`, que seleciona uma demo
offline antes de qualquer inicialização de transporte. A mesma demo pode ser
aberta explicitamente com `--mode=demo`, mas nunca é fallback de erro de rede.
Seu controlador gera apenas estados descartáveis para a apresentação e não cria
`MultiplayerPeer`, não usa RPC e não instancia a autoridade do servidor.

O preset Web desativa threads para permitir inspeção local com um servidor HTTP
simples. Pull requests validam e geram o artifact sem publicar. O deploy em Pages
só ocorre após execução manual ou push em `main`, depois de todos os testes e da
verificação do conteúdo exportado; Railway continua fora deste marco.

Neste marco o preset inclui todos os recursos para reduzir o risco de omitir uma
dependência da demo. Isso também inclui scripts do servidor no PCK e não deve ser
considerado proteção de segredos; antes de adicionar papéis ou compras secretas,
o export deverá selecionar estritamente os recursos do cliente.

## Marco 3: fundações do ciclo de partida

A rodada vive em três camadas separadas. `shared/round_state.gd`,
`shared/role.gd` e `shared/round_rules.gd` guardam apenas regras determinísticas
sem estado: a matriz de transições, os papéis, o sorteio com RNG injetável, a
avaliação de vitória e os sanitizadores. `server/lobby_registry.gd` é o registro
oficial das sessões conectadas e `server/round_authority.gd` é a autoridade
headless que combina os dois. A camada de rede em `shared/network_app.gd` só
traduz eventos em RPC; `client/round_hud.gd` só formata o que chegou.

A autoridade não usa `Timer` nem nós: ela recebe o tempo do servidor por
`tick(now_msec)` e mantém prazos como marcos absolutos em milissegundos. Isso
torna os testes determinísticos, mantém a lógica independente de cena, de
renderização e do transporte, e preserva a troca futura de WebSocket por
ENet/UDP. Cada prazo guarda o `round_id` que o criou e é revalidado antes de
disparar, portanto um callback atrasado não altera a rodada seguinte.

O `round_id` avança ao entrar em `COUNTDOWN`. Um countdown cancelado consome o
identificador, de modo que a tentativa seguinte nunca reaproveita o número de uma
rodada anterior. O reinício apaga papéis, vivos, eliminações, vencedor e prazos
antes de voltar ao lobby e só então reavalia a elegibilidade.

O sigilo é estrutural, não convencional. O mapa de papéis fica privado em
`RoundAuthority`; a rede pede um papel por vez com `get_role_for_peer()` depois
de `can_deliver_role()` confirmar destinatário, participação e fase, e envia por
`rpc_id`. Não existe RPC de escolha ou consulta de papel, nem de morte declarada
pelo cliente. O servidor desliga `SceneMultiplayer.server_relay`, removendo o
caminho cliente→cliente que permitiria um peer se passar pelo servidor. Os logs
de produção trazem apenas contagem agregada de papéis.

Protocolo na versão 3, incompatível com clientes do marco de movimento: o join
passou a ser validado pelo `LobbyRegistry` e o estado público da rodada, o roster
seguro e a entrega privada do papel são mensagens novas. As mensagens ficaram em
três categorias: públicas em broadcast (`round_public_state`, `round_roster`),
privada por destinatário (`round_private_role`) e internas do servidor (mapa de
papéis, seed, avaliação de vitória, transições), que não trafegam.

Neste marco o movimento continua liberado em qualquer fase. Bloquear ação por
fase muda o comportamento validado pelo teste de movimento existente e pertence
ao marco de combate, junto com o primeiro uso real de `eliminate_player()`.

O export Web ainda usa `export_filter="all_resources"` e portanto continua
embarcando os scripts do servidor no PCK. Isso não expõe segredo de partida — a
demo offline nunca instancia a autoridade e nenhum papel é sorteado no cliente —
mas a restrição registrada no marco visual permanece: antes de multiplayer Web
público, o preset precisa selecionar estritamente os recursos do cliente.

## Auditoria do marco 3: precondição do reinício

O reinício da rodada passou a validar a própria fase em vez de delegar a
checagem à matriz de transições. `COUNTDOWN -> WAITING` é uma transição legítima
— é assim que um countdown é cancelado quando o lobby cai abaixo do mínimo —,
portanto `reset_for_next_round()` apoiado apenas em `_transition()` aceitava ser
chamado durante uma contagem regressiva válida: cancelava a contagem, reiniciava
o prazo e consumia um identificador de rodada, tudo sem registrar transição
inválida. O reinício agora só existe a partir de `ENDED`; qualquer outra origem é
contabilizada como transição inválida e ignorada.

Pela mesma razão, `_begin_countdown()` limpa explicitamente papéis, participantes,
vivos e eliminações. Hoje só se chega a `COUNTDOWN` vindo de `WAITING`, que já
está limpo, mas `ENDED -> COUNTDOWN` é uma transição declarada válida na
especificação: limpar na entrada garante que nenhum papel da rodada anterior
sobreviva caso esse caminho passe a ser usado.

Registros indexados por `peer_id` são limpos quando o peer sai. O teste
adversarial fixa essa invariante estruturalmente, comparando o conjunto de
dicionários limpos no encerramento com os limpos na desconexão.

## Marco 4: primeiro combate autoritativo

`CombatAuthority` é headless e compõe `RoundAuthority`, `AuthoritativeWorld`,
`InventoryAuthority` e `CombatRules`. A rodada continua dona de eliminação e
vitória; o mundo é a fonte de posição e yaw; a pistola server-owned fornece 34
de dano, carregador 6, reserva 18, cadência de 400 ms, alcance 20 m e recarga de
1,2 s.

Cada entrada em `ACTIVE` recria quatro armas e quatro caixas com IDs estáveis e
`round_id`. Vida, inventário, munição e recarga são privados; pickups e efeitos
usam DTOs públicos por allowlist, sem papéis. A coleta é síncrona, então a
primeira intenção válida torna o pickup indisponível antes da publicação.

O servidor headless resolve hitscan analítico contra os AABBs de `ArenaRules` e
hitboxes vivas. A mesma geometria é apresentada pelo cliente. A origem efetiva é
sempre o olho oficial e a direção precisa ser finita, normalizada e compatível
com o yaw oficial. Parede bloqueia alvos; atirador e mortos são ignorados.

As intenções reliable de coleta, disparo e recarga usam remetente derivado por
`get_remote_sender_id()`, sequências independentes, deduplicação, salto limitado
e rate limit. Argumentos de borda são `Variant` validados. O protocolo é versão
4. Viewmodel, pickups, mira, tracer, hit marker e HUD existem só no cliente
gráfico; a demo offline permanece isolada.

## Marco 5: revelação final e espectador básico

`RoundAuthority` continua como única fonte de papéis, vida e vitória. Ela cria
uma única revelação sanitizada somente depois da transição oficial para `ENDED`,
antes de apagar `_roles`; a rede a entrega por `rpc_id` apenas aos participantes
ainda conectados. O DTO contém exclusivamente rodada, equipe, razão e identidade
pública/papel final. O reset limpa DTO e papéis, e o acesso retorna vazio fora de
`ENDED`, impedindo consultas precoces e callbacks atrasados.

A autorização do espectador também permanece em `RoundAuthority`. Cada morto
recebe privadamente a lista recalculada de participantes vivos e conectados da
rodada, sempre sem si próprio. Não existe RPC de escolha: Q/E apenas percorre a
lista já autorizada no cliente. `ArenaView` posiciona a câmera pela posição e yaw
dos snapshots oficiais; não há câmera livre nem controle do observado. O cliente
cessa movimento, pickup, tiro e recarga, mantendo as validações do servidor como
defesa em profundidade.

O HUD apresenta estado privado e resultado sem calcular vida, papel ou vencedor.
Servidor headless segue sem apresentação e a demo offline não simula esses
estados. O protocolo passa à versão 5. As validações específicas são os testes
`spectator_reveal_authority_test.gd`, `spectator_reveal_client_test.gd` e
`spectator_reveal_network_test.sh` (servidor + quatro clientes).

## Marco 6: arena graybox jogável

A arena passou a ser uma única lista de AABBs em `ArenaRules.BLOCKERS`, usada
pelo hitscan de `CombatAuthority`, pela nova colisão de movimento e pela
apresentação. `ArenaView` gera exatamente uma mesh por bloco, com o mesmo centro
e tamanho; qualquer outra mesh é decoração plana de piso (faixas de região e
marcas de spawn, no máximo 2 cm) e as placas ficam coladas nos muros externos.
O teste `arena_layout_test.gd` instancia a arena do cliente e compara nó a nó.

Não há pulo nem mira vertical: o tiro sai horizontal no olho oficial (1,7 m).
Por isso os blocos têm três alturas bem separadas do olho: parede 3,0 m e
cobertura 2,4 m bloqueiam visão e tiro; caixote baixo 1,0 m bloqueia passagem,
mas visão e tiro passam por cima. Todo bloco nasce no piso, então nada passa por
baixo. A hitbox oficial do corpo foi centrada na posição oficial, como a cápsula
do cliente (0–2 m); como todo tiro é horizontal a 1,7 m, isso não muda nenhum
acerto, só elimina a divergência entre corpo visível e corpo atingível.

O movimento autoritativo agora colide com os blocos: cada eixo é resolvido em
separado (permite deslizar em parede), o passo é subdividido em trechos de até
0,2 m (menores que o bloco mais fino, 0,5 m) e um corpo teleportado para dentro
de um bloco não fica preso. O limite do corpo passou a 14 m, meio metro antes
da face interna dos muros externos (14,5 m).

O layout tem simetria rotacional de 90°: pátio central com monumento, quatro
bordas com uma arma e cobertura em cata-vento, e quatro salas de canto com porta
diagonal. Os quatro primeiros spawns ficam nas salas; os demais atrás de
coberturas largas nas bordas, e todos nascem olhando para o centro. Os testes
exigem: nenhum spawn sobre pickup ou preso, passos livres em oito direções,
nenhum par de spawns com linha de tiro pelo hitscan oficial, todo pickup
coletável pelo caminho oficial e alcançável de todo spawn mesmo com qualquer um
dos cinco corredores principais selado, e lados opostos conectados por pátio,
corredor leste e corredor oeste isoladamente. As faixas usadas pelos testes de
combate existentes foram preservadas; o teste de fumaça passou a ler o limite
da arena da regra oficial em vez de repetir o valor antigo.

Cores e placas por região, o indicador **Região** do HUD e as luzes coloridas
sem sombra são apresentação pura. A demo Web continua **OFFLINE / SEM SERVIDOR**:
mostra a nova arena e usa a mesma colisão para a caminhada local, sem simular
rodada, combate ou rede.

## Correção: encerramento correlacionado por geração e token

O `shutdown_ready` não tinha argumentos, e o servidor aceitava qualquer ready de
um peer esperado assim que entrava em shutdown (achado F4/F7 da auditoria). No
teste adversarial, o join do atacante tardio inicia o encerramento. O ready
"não solicitado" que ele envia ao ser aceito era contado como legítimo, e o
servidor podia fechar antes de o atacante processar a preparação. Isso gerava a
falha intermitente `combat-probe-sent-pickup_during_shutdown` no CI.

`ShutdownHandshake` (headless, em `server/`) agora abre uma geração por
tentativa. Ele sorteia um token por peer no instante em que registra o envio da
`shutdown_prepare(generation, token)` para aquele peer. Uma
`shutdown_ready(generation, token)` só conta se:

- o remetente vem de `get_remote_sender_id()`;
- o peer é esperado e continua no lobby;
- a preparação dele já foi enviada;
- a geração é a corrente;
- o token é exatamente o entregue a ele;
- ainda não houve confirmação desse peer.

Confirmações antecipadas, adivinhadas, obsoletas, duplicadas, de tipo errado ou
de peers não esperados são recusadas. Cada motivo é registrado uma vez por peer
e nenhum avança a contagem. O cliente só confirma uma preparação vinda da
autoridade, uma única vez, e para de enviar RPC depois dela. Um peer esperado
que se desconecta durante o encerramento deixa de ser aguardado, e os demais
concluem sem cair no timeout. O protocolo passa à versão 6.

O teste adversarial agora fixa a ordem que antes era sorte: o atacante só entra
depois das quatro confirmações de papel, e processa a preparação com meio
segundo de atraso. Com o protocolo antigo, esse cenário falha em 3 de 3
execuções. `shutdown_handshake_test.gd` cobre cada motivo de recusa de forma
determinística.

## Teste local no PC: menu, servidor hospedado e build Windows

O jogo exportado para Windows (feature `desktop_playtest`) e a execução gráfica
sem argumentos abrem um menu. A demo Web tem a feature `visual_demo`, avaliada
antes, e continua OFFLINE / SEM SERVIDOR.

"Criar partida local" nunca instancia autoridade no processo do jogador. O
`DesktopSession` confere a porta e inicia o mesmo executável com
`--headless -- --mode=server --status-file=... --hosted=true`. O servidor grava
`ready` ou `error:unable_to_listen` nesse arquivo, e só com `ready` o menu
conecta a janela do anfitrião como cliente comum em loopback. Assim a sala nunca
é declarada criada antes de o servidor realmente escutar. A escuta é em
`127.0.0.1` por padrão; `0.0.0.0` só com a opção LAN marcada. Um segundo
"Criar" na mesma porta cai em porta ocupada, e o mesmo processo não inicia um
segundo servidor.

Não sobra processo órfão:

- voltar ao menu, sair, fechar a janela ou encerrar a árvore mata o servidor que
  aquele processo hospeda;
- se o jogo do anfitrião morrer sem conseguir isso, o servidor `--hosted` se
  encerra sozinho após 20 s com o lobby vazio.

Quando o anfitrião sai, os demais recebem a desconexão e voltam ao menu. O
encerramento em duas fases continua sendo usado nos testes. Na sessão de PC o
anfitrião derruba o processo, o que é aceitável porque a partida acaba com ele.

No modo interativo, falha de conexão, recusa, timeout e desconexão levam de
volta ao menu (recarregando a cena), em vez de encerrar o processo. Os clientes
de teste headless mantêm o comportamento anterior. O projeto passa a dar flush
no stdout a cada `print` (`application/run/flush_stdout_on_print`): sem isso,
os templates release retêm os marcadores de log, e o log do servidor hospedado
ficaria incompleto se o processo fosse encerrado.

O preset "Windows Desktop" embute os dados no `.exe` e gera também o wrapper
`.console.exe`. Ele exclui `tests/` e `build/` e não altera o recurso do
executável (sem rcedit/assinatura). O PCK inclui os scripts do servidor, porque
o mesmo executável é o servidor hospedado. Ele não contém segredos e não deve
ser tratado como proteção. O workflow *Godot Windows playtest build* exporta no
Ubuntu, publica o ZIP como artifact do PR (sem release) e roda
`desktop_local_match_test.sh` contra o `.exe` exportado num runner
`windows-latest`, sem o projeto. As condições do deploy do GitHub Pages não
mudaram.

## HUD de partida (vivo, espectador, fim de rodada)

O HUD (`client/round_hud.gd`) é uma projeção pura dos dados oficiais que o
cliente já recebe. `RoundHud.view_model(...)` monta o que aparece a partir
desses dados, e os nós só desenham o resultado. Não houve RPC nova nem mudança
de regra.

- Papel, vida, arma e munição aparecem só quando o `round_id` do dado privado é
  o da rodada pública atual. Ao voltar para WAITING/COUNTDOWN, o cliente limpa
  o estado de combate local. Assim, uma rodada nova nunca mostra valores da
  anterior.
- Espectador: o alvo é o que o servidor autorizou
  (`round_private_spectator_targets`) e Q/E só alternam entre esses alvos.
  Mira, arma e painéis privados ficam ocultos.
- Fim de rodada: vencedor e motivo vêm do estado público `ENDED`. Os papéis só
  aparecem com o `round_final_reveal` da mesma rodada, e os nomes vêm do roster.
- A recarga aparece apenas como texto ("RECARREGANDO"). O estado privado só traz
  `reloading: bool`, sem prazo, então não há barra de progresso.
- A cor e o tamanho da vida baixa derivam de `CombatAuthority.MAX_HEALTH` e do
  dano da pistola, e há teste que confere os dois.
- O layout é desenhado em 960×540 com `stretch/mode=canvas_items` e
  `aspect=expand`, e escala para 1920×1080. Os painéis ficam nos cantos e na
  faixa superior/inferior, e o centro da tela fica livre para a mira.
- A checagem de layout (`tests/hud_presentation_test.gd`) precisa de
  renderização real (xvfb). Em headless ela é pulada com marcador explícito, e
  por isso esse teste ainda não está no CI.

## Correção: frente visível do avatar remoto

Quem estava sem arma parecia "olhar fixo" para os outros jogadores. A causa não
estava na rede nem na autoridade:

- o servidor aplica o yaw com ou sem arma;
- o snapshot leva esse yaw;
- o cliente já girava o nó do avatar para o valor oficial.

O problema era o modelo: uma cápsula simétrica em Y, que não tem frente, então a
rotação aplicada não aparecia. Com arma, os traçados dos disparos davam a
impressão de direção.

A correção adiciona ao avatar remoto um visor, uma malha sem colisão em -Z local
(a mesma convenção da câmera), que herda o yaw oficial do nó. O disparo continua
usando a direção da câmera local, que segue o yaw oficial do snapshot. A
autoridade valida o disparo pelo seu próprio yaw, então nada visual altera o
raycast. Em primeira pessoa como espectador, o visor do alvo observado fica
oculto para não aparecer colado à lente. `tests/avatar_facing_test.gd` mede a
frente visível no mundo, e não só `rotation.y`, e roda no CI.

## Fase 2: primeira versão visual dos personagens e objetos

Os modelos são procedurais, montados com primitivas do Godot em
`client/arena_models.gd`. Não havia modelos externos no repositório, então os
modelos do Gemini e do Kimi não foram avaliados.

**Troca de modelo.** Para trocar um modelo, basta criar a cena correspondente
em `res://assets/models/` (`character.tscn`, `pistol.tscn`, `ammo_box.tscn`),
que é instanciada no lugar da versão procedural. O personagem precisa manter a
frente em -Z local e um filho `FacingVisor`. Nenhum modelo pode trazer colisão.

**Direção visual.** Silhuetas escuras de sobretudo e chapéu, rosto sem traços e
um único acento de cor por jogador (cachecol e fita do chapéu), para
diferenciar pessoas. O modelo é o mesmo para todos os papéis: ele só recebe o
`peer_id`. A frente aparece pelo visor e pelas lapelas.

- A pistola na mão é a mesma do chão.
- Pickups de arma têm halo ciano (frio). A caixa de munição tem pontas de latão
  e halo cobre. O amarelo continua exclusivo dos caixotes baixos.
- Os pickups giram devagar só no nó visual interno. A posição oficial de coleta
  não muda.

**O que não mudou.** Colisão, posições de coleta, raycast, dano, munição,
papéis, privacidade e controles. A arma na mão segue apenas o inventário
privado oficial (`combat_private_state`). O personagem remoto não mostra arma:
isso exigiria publicar quem está armado, o que esta fase não altera.

Como espectador em primeira pessoa, o modelo inteiro do alvo fica oculto, para
não aparecer colado à câmera.

**Testes.** Com um corpo humano simétrico, `tests/avatar_facing_test.gd` passa a
medir a frente pela soma dos deslocamentos das peças: as peças simétricas se
anulam e a cápsula antiga ainda falha. `tests/arena_visuals_test.gd` cobre
posições, disponibilidade, arma na mão, ausência de colisão e silhueta igual
para todos, e roda no CI.

## Fase 3: HUD visual dentro da partida

O HUD continua sendo só uma projeção de dados oficiais que o cliente já recebe:
não há RPC nova nem mudança de regra, autorização, privacidade ou vitória.

**Avisos de combate**
- Os avisos negativos vêm da recusa oficial (`combat_action_rejected`), que o
  servidor envia só a quem agiu. Motivos que o jogador pode corrigir viram
  texto, e o pente vazio diz "R" ou "procure munição" conforme a reserva
  oficial. Cadência, dados técnicos e rodada encerrada ficam em silêncio.
- Os avisos positivos ("PISTOLA EQUIPADA", "+6 MUNIÇÃO", "RECARREGADA") vêm da
  diferença entre dois estados privados oficiais seguidos da mesma rodada.

**Prompt de coleta**
- Usa o mesmo pickup que E pediria: posição oficial mais estado público dos
  pickups.
- O texto segue as regras do servidor: uma arma por vez, munição só com arma e
  reserva abaixo do máximo.

**Painel da arma e vida**
- O painel da arma ganhou as balas do pente e uma faixa de recarga que corre sem
  prometer duração, porque o estado privado só traz `reloading`.
- A barra de vida ganhou marcas a cada dano de um tiro da pistola.
- Capacidade, reserva máxima e caixa de munição conferem, em teste, com os
  valores do servidor.

**Eliminações**
- O feed usa o evento público `combat_public_elimination` e mostra só o nome,
  sem autor nem papel, em texto neutro ("fora da rodada").
- Aparece para vivos e espectadores e é limpo em ENDED e na rodada seguinte,
  junto com avisos e prompt.

**Correções na ArenaView reveladas pela partida real**
- O próprio jogador não ganha mais corpo enquanto observa outro.
- Ao sair do modo espectador, a câmera volta na hora à última posição oficial do
  próprio jogador, em vez de ficar alguns quadros dentro do corpo do alvo.
- Quem foi eliminado volta a aparecer quando o roster oficial o marca vivo na
  rodada seguinte.

`tests/match_hud_test.gd` (nós reais, no CI) cobre a sequência vivo →
eliminado → espectador → ENDED → nova rodada. `tests/hud_presentation_test.gd`
mede o layout dos novos elementos em 960×540 e 1920×1080.

## Fase 4: efeitos e sons das ações de combate

Todo efeito nasce de um evento oficial que o cliente já recebia; nenhuma RPC,
dano, cadência, munição, raycast ou regra de vitória mudou.

| Ação | Evento oficial | Efeito |
|---|---|---|
| Coleta aceita | estado privado (arma nova ou reserva maior sem recarga) | som `pickup_ok` |
| Coleta/ação recusada | `combat_action_rejected` (só para quem agiu) | som `pickup_deny` (ou `dry_fire` no pente vazio), nunca o de sucesso |
| Pickup some | `public_pickups` (`available` false) | anel neutro no lugar, igual para todos, sem dizer quem pegou |
| Próprio disparo | `combat_public_shot` com `shooter_peer_id` próprio | som, recuo e clarão só na pistola da mão |
| Disparo alheio | `combat_public_shot` | clarão fraco e som posicional na origem pública |
| Impacto | `end` e `hit_player` públicos do disparo | marca de parede ou de jogador (quem foi atingido não é revelado) |
| Acerto confirmado | `combat_hit_confirmed` (só para quem atirou) | marcador da mira (já existia) e som `hit` |
| Dano recebido | vida privada oficial diminui na mesma rodada | som `hurt`, tranco curto e a vinheta de borda que já existia |
| Recarga | `reloading` oficial false→true e true→false com pente maior | sons de início e fim; pistola inclinada enquanto a recarga oficial durar |
| Eliminação | `combat_public_elimination` | fumaça cinza neutra no corpo e som, sem cor de papel |

- **Mira:** recuo e pose de recarga mexem só num pivô da pistola. O tranco de
  dano usa `v_offset`/`h_offset` da câmera, que não mudam a origem nem a direção
  usadas no disparo.
- **Impacto na própria câmera:** um impacto colado na câmera (quem foi atingido
  é você) não é desenhado.
- **Discrição:** clarões duram 60 ms, a luz tem energia máxima de 0,9 e não há
  flash de tela. Todos os efeitos somem sozinhos em menos de 1 s e são limpos
  quando o cliente zera o estado de combate entre rodadas.
- **Áudio:** `client/sfx_bank.gd` gera 9 sons curtos (PCM 16 bits, 22 050 Hz)
  com seno, ruído de semente fixa e envelopes. Não há arquivo de áudio externo
  nem licença de terceiros, e o mesmo código roda em Windows e na Web.
- **Testes:** `tests/combat_feedback_test.gd` confere evento → efeito e roda
  no CI.

## Personagens GLB e aparência pública

Os jogadores remotos usam os oito personagens do pacote `personagem_3d`
(branch `main`, pasta `models/`), copiados para `assets/characters/` e
importados pelo Godot. Não há download em tempo de execução. Os modelos foram
gerados proceduralmente para o projeto (`tools/generate_characters.py` daquele
repositório, sem recursos externos). O repositório de origem não declara
licença.

**Atribuição da aparência**
- O servidor escolhe a aparência na entrada da sessão (`LobbyRegistry.add`),
  antes de existir papel: a primeira variante livre entre as sessões
  conectadas, na ordem de `CharacterAppearance.IDS`.
- Com até oito sessões, as variantes são distintas. A aparência é estável
  durante a sessão, e quem sai libera a sua variante.
- Nunca deriva de papel, equipe, inventário ou estado privado.

**Protocolo 7**
- O roster público carrega `appearance`.
- O cliente só aceita as chaves `peer_id`, `label`, `connected`,
  `participant`, `alive` e `appearance`. Um id fora da allowlist vira `ember`
  e nunca monta caminho de arquivo.
- Quem entra tarde recebe o roster completo, como antes.

**Visual**
- Os GLBs têm origem nos pés, 1,80 m, +Y para cima e frente +Z, sem rig nem
  animação.
- Só o nó visual `CharacterModel` é ajustado: desce `PLAYER_HEIGHT` (a posição
  oficial é o centro do corpo) e gira meia volta (a frente do jogo é −Z). A
  escala é real.
- Controlador, colisão, hitbox oficial, câmera, tiro e raycast não mudam.
- O próprio jogador nunca tem corpo, e no espectador o modelo do alvo fica
  oculto.
- Não há animação de caminhada, porque os arquivos não têm rig. O corpo desliza
  e gira pela posição e pelo yaw oficiais.

**Importação**
- `generate_lods` e `ensure_tangents` estão desligados: cerca de 560
  triângulos e nenhum normal map.
- A importação headless do editor imprime `Parameter "t" is null` uma vez por
  GLB novo, inclusive para um GLB mínimo gerado pelo próprio Godot. É ruído do
  editor sem tela, e a importação termina com código 0.

## Mira vertical (pitch) oficial

**Fluxo**
- O cliente acumula o movimento vertical do mouse em `pitch_delta` (limitado a
  `MAX_PITCH_DELTA` por envio) e o envia em `submit_input` junto com o yaw.
- O servidor rejeita valores não finitos, deltas grandes demais e excesso de
  taxa (balde próprio, `MAX_PITCH_RATE`). O pitch oficial fica em ±75°
  (`MovementRules.MAX_PITCH`) e vai no snapshot.
- A câmera usa só o pitch oficial, como já fazia com o yaw. Não há predição
  local. O espectador aplica o pitch do alvo.

**Protocolo 8**
- `submit_input` ganhou `pitch_delta`, e o snapshot ganhou `pitch`.

**Disparo**
- O servidor valida o rumo horizontal declarado contra o yaw oficial, como
  antes. A inclinação declarada pode divergir no máximo 25° do pitch oficial,
  para tolerar latência.
- O raio usa sempre o pitch oficial (`WeaponRules.official_shot_direction`).
  O ponto de impacto declarado continua proibido.
- O raycast oficial passou a considerar o piso (`ArenaRules.ray_floor`). Não
  há teto, então um tiro para cima sem obstáculo termina no alcance máximo.

**Cabeça visível**
- Os GLBs não têm ossos nem animação. Cabeça, nariz, olhos e cabelo são
  malhas irmãs com transformação identidade.
- Ao montar o avatar, essas malhas passam a um pivô `HeadPivot` na base da
  cabeça (1,57 m), compensadas para ficar no mesmo lugar em repouso.
- Os demais clientes giram só esse pivô em X pelo pitch oficial, limitado a
  ±40°. Pescoço, tronco, raiz do avatar e colisão não inclinam.

## Mansão jogável (fase 1)

Detalhes, dimensões e checkpoint: `docs/mansion-plan.md`.

**Fonte única do mapa**
- A arena graybox saiu. `shared/mansion_map.gd` declara:
  - cômodos e corredores;
  - portas e junções;
  - móveis;
  - spawns e pickups.
- Paredes, vergas e tetos são derivados de forma determinística. Uma parede
  esquecida não deixa canto aberto.
- `ArenaRules` mantém a API de antes (`BLOCKERS`, `PICKUP_POSITIONS`, `ZONES`,
  raycasts, `overlaps_blocker`) e lê desses dados. Servidor, cliente e testes
  não mantêm coordenadas próprias.

**Colisão e tiro oficiais**
- O movimento segue o mesmo algoritmo: circunferência contra AABB, por eixo,
  com sub-passos de 0,2 m. Duas mudanças:
  - ignora volumes acima do corpo (vergas e tetos);
  - consulta um índice em baldes de 4 m.
- O limite simétrico da arena virou um retângulo de segurança
  (`MAP_MIN/MAX_X/Z`). Quem fecha a casa são as paredes.
- O tiro para no primeiro contato entre piso, paredes, batentes, vergas,
  tetos, móveis e jogadores.
- Mesas são tampo e pés: embaixo delas o tiro passa, e o corpo é barrado pelo
  tampo.

**Regras preservadas**
- Tipos, quantidades, distâncias e índices dos pickups continuam os mesmos
  (0..3 armas, 4..7 munição).
- Oito spawns, na mesma ordem de ocupação.
- A nova rodada continua sem reposicionar jogadores, como antes. O teste de
  oito clientes confirma que ninguém começa dentro de um volume.

**Correção encontrada pelo teste de oito clientes**
- Um cliente encerrado corretamente pelo servidor podia sair com
  `CLIENT_TIMEOUT` quando a sessão passava de 10 s. O prazo de conexão era
  avaliado depois do desligamento combinado.
- Agora o prazo não vale depois de `shutdown_prepare_received`.

**Testes de rede**
- `combat_network_test.sh` aceita `COMBAT_CLIENTS` e `COMBAT_EXTENDED`.
- Com oito clientes, o modo estendido cobre:
  - vítima eliminada no meio da rodada, que passa a espectadora;
  - fim da rodada;
  - rodada seguinte, com oito pickups sem duplicação, corpos livres e
    aparências mantidas.
