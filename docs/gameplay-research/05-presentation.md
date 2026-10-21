# SPEC 05 — apresentação FPS

A câmera FPS continua regida exclusivamente por `ArenaView._write_rig`.
`CameraEffects.sample(speed, delta)` produz apenas a transformação do filho
`PresentationMotion`; não recebe estados de previsão nem escreve posição,
yaw/pitch, origem ou direção do tiro. Recoil e recarga permanecem no filho
`WeaponPivot`, com o tween existente como único escritor dessa pose. Não há
ADS, mudanças de sensibilidade, estados DOWNED ou animação vertical nova.
Avatares remotos mantêm interpolação e animação procedural autoritativa existentes.

## Parâmetros e uso

Bob: ±0,009 m horizontal e ±0,006 m vertical, fase 9 rad/s e frequência
vertical dupla. Sway: yaw ±0,012 rad e roll ±0,009 rad. Amplitude acompanha
velocidade horizontal oficial, saturada em 6 m/s, com resposta exponencial
12/s. `strength` entre 0 e 1 reduz o efeito; zero retorna identidade e reinicia
fase/amplitude. Entradas não finitas retornam identidade. A velocidade usada
é a do último snapshot local, sem derivar passos de correções de posição.

A preferência existente “reduzir movimento” é lida ao criar a arena, propagada pelo sinal de configurações durante a sessão e desliga
bob/sway, recoil e tranco de dano. `set_presentation_motion(false)` desliga e
reseta imediatamente. Morte, espectador, ausência de arma, UI fora de gameplay
ou arena oculta limpam efeitos; a câmera não muda de orientação nem posição.
A pose funcional de recarga é preservada. O recoil existente recupera em
0,04 + 0,12 segundos; bob/sway têm escritor separado e não brigam com ele.
Não foi acrescentado recoil de câmera: o tranco de dano existente continua
limitado aos offsets de projeção (0,035 / 0,0175), nunca ao rig.

## Correções reproduzidas

`show_shot` chamava `look_at` antes de `add_child`, produzindo erro de engine
e tracer desalinhado. Agora entra na árvore, recebe centro global e só então
olha ao endpoint; segmento vertical usa up alternativo e segmento zero não
tenta orientação indefinida. O teste real verifica a direção da mesh.

Os avisos de owner vinham tanto da montagem de `HeadPivot` em `ArenaModels`
quanto de `CharacterRig._adopt`: malhas importadas eram adicionadas ao novo
pai com owner transitório inconsistente. Nos dois caminhos, o owner é limpo
antes de remover e restaurado após adicionar ao ancestral correto. Não há mudanças de assets.

## Verificação

Godot 4.4.1, com env/XDG fixados. `camera_effects_test` verifica identidade,
bounds finitos, repouso, recuperação do recoil, equivalência de um segundo
em 20/60/144 FPS, igualdade exata de estado oficial/origem/direção da câmera,
reset imediato ao desativar/morrer/espectar e orientação real de tracer.
A câmera permanece no mesmo ponto junto a paredes: os efeitos movem somente
a arma, sem possibilidade de obter uma nova origem de visão ou tiro.

Os testes camera_effects, combat_feedback (84), character_animation (472),
character_appearance (142), avatar_facing (27), vertical_aim (81),
spectator_reveal_client (16), round_reset_bodies (259) e menu (194) passaram
com exit 0. Combat_feedback e avatar_facing mantêm o aviso preexistente
ObjectDB instances leaked at exit; não apareceu erro de look_at nem de owner.
Logs completos: estado local `mission-sdd/spec05/`.

## Referência e limites

TPS Demo, SHA `a82f15448e9b015440d3bbdf5e10801b260c4e9f`, usado apenas como
referência conceitual de separar entrada, modelo e estados de apresentação.
O HEAD declara Godot 4.7, incompatível com assumir execução direta no 4.4.1.
Nenhum código, asset ou mídia foi importado; vale o inventário de licenças
existente. A implementação é própria.

A sessão gráfica usa Xorg dummy, Compatibility e Mesa llvmpipe (software).
Isso confirma execução gráfica local, não certifica qualidade perceptiva,
GPU real, desempenho Android/Web nem conforto de movimento humano.

A sessão gráfica do mesmo teste também passou com `CAMERA_EFFECTS_TEST_OK`,
exit 0, renderer Mesa llvmpipe; aviso de V-Sync não suportado pelo driver dummy.
A recuperação do recoil é verificada após 30 frames, evitando confundir tempo
de parede durante construção de cena com tempo efetivamente processado do tween.

`spectator_reveal_network_test.sh` passou: `SPECTATOR_REVEAL_NETWORK_TEST_OK
clients=4`, exit 0. `combat_network_test.sh` falhou com exit 1 em CONTEST,
actions=0, acks=2. Investigação independente identificou corrida de inicialização
do harness: ACK da ação pode preceder sincronização da época e a fila é limpa.
Isso exige correção separada e nova execução antes de declarar a integração
multiplayer desta etapa completa; não se atribui sucesso a esse teste.
