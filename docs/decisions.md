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
