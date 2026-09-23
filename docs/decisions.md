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
