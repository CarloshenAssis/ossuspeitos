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
