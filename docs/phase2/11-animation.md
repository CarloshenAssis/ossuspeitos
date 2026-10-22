# SPEC11 — ações e transições visuais

## Entrega

`CharacterActionState` é um estado procedural puro e limitado, separado da autoridade. Prioridade: morte > impacto > disparo > recarga > interação. Envelopes por tempo em segundos fazem a mesma pose em30/60/120FPS, expiram e retornam à locomoção. Morte bloqueia ações posteriores até reset. Nenhum estado visual escreve dano, munição, velocidade, raiz oficial, câmera, hitbox ou RPC.

`CharacterAnimator` conserva idle/walk, fase por distância e rig/modelos existentes. Sobrepõe apenas ombros/cotovelos/tronco após a passada. Reset de época/teleporte e reaparecimento eliminam ações transitórias. Não há corrida/sprint oficial; não foi inventada uma regra de velocidade para preencher uma animação.

`ArenaView` recebe disparo do evento público já autorizado; porta/recarga/manuseio vêm do catálogo de eventos por sala. `handle` é emitido somente após a autoridade aceitar pegar/soltar/empurrar. Os IDs de rodada/evento são deduplicados antes da animação, independentemente de volume, distância ou decisão de tocar áudio. Bootstrap/reconexão não reproduz poses antigas; evento de rodada anterior ou ator morto não reinicia ação. Nova rodada limpa poses.

Reação remota a impacto é uma aproximação cosmética baseada **somente** no `hit_player` e endpoint públicos do disparo, procurando avatar próximo. Não transmite identidade privada do alvo, saúde ou papel, nem decide acerto. O feedback local de dano existente permanece no estado privado.

Morte mantém o avatar oficial oculto e cria o corpo sanitizado existente. Uma transição curta de acomodação dos braços do cadáver termina na pose anterior; não é ragdoll nem simulação de queda. A raiz/ângulo de queda não mudam e o apoio no piso é recalculado da malha. Reduzir movimento cancela essa transição imediatamente. Nenhuma geometria de colisão é criada pelo efeito.

## Alternativas

State Charts foi estudado no inventário de referências. Para cinco ações finitas, o plugin e um grafo duplicariam estado sem benefício suficiente; enum/string allowlisted e duração/prioridade bastam. AnimationTree não substituiu os rigs procedurais. Nenhum código/asset externo foi incorporado.

## Evidências

Logs: `/workspace/.ossuspeitos-state/phase2/spec11/`.

- RED inicial: `procedural action state exists` antes da implementação.
- Novo teste: **35checks headless PASS**, cobrindo prioridades, expiração,30/60/120FPS, pose efetiva no ombro durante movimento, raiz/mira intocadas, porta com áudio mudo, deduplicação, disparo/impacto oficial, morte/interrupção, rodada antiga, reset e acomodação do corpo.
- Reduzir movimento inicialmente deixou a transição ativa até o próximo frame: teste reproduziu35checks/1falha; correção cancela e restaura no próprio setter. GREEN em `green-final.log`.
- Smoke gráfico real Compatibility/X11/Mesa llvmpipe: **36checks PASS**, sem erro de engine/script; screenshot `character-actions.png` mostra avatar com pose e corpo na mansão. Renderização por software; não certifica GPU física ou conforto humano.
- Suíte completa é executada via `python3 tests/run_phase2_unit_tests.py --logs .../spec11/final-units`; **40/40 PASS** na revisão final, exit0 e marcadores obrigatórios sem SCRIPT ERROR/Parse Error/engineERROR; inclui o setter de cancelamento final. A execução anterior também passou40/40.

Não há animações de clips importados, sprint real, ragdoll ou inferência de papel. Estado remoto sob atraso real, quatro/oito clientes e reinício integrado pertencem ao SPEC16; os testes de evento atrasado/deduplicado daqui são locais e não substituem essa campanha.
