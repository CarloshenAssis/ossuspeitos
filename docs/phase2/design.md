# Fase 2 — desenho de integração

Base confirmada: PR30 e PR31 abertos; main dd15ff2; PR31 final59926cb. Branch codex/gameplay-specs-09-16. Godot4.4.1, Compatibility, servidor WebSocket autoritativo. Master spec: master-spec.md.

## Alternativas e escolha

1. Simular todo o cenário em RigidBody/Jolt: boa variedade, mas replay/plataformas não determinísticos e custo de replicação; rejeitado para bloqueadores competitivos.
2. Volumes analíticos autoritativos por sala, dinâmica limitada e apresentação interpolada: escolhido. Preserva geometria existente, estados limitados, colisão/tiro consultam os mesmos volumes; Physics/Jolt ficam no laboratório comparativo.
3. Objetos somente cosméticos: barato, porém não cumpre portas/obstáculos compartilhados; restrito a efeitos decorativos.

## Contratos

InteractionAuthority por MatchRoom controla definições, posse, estado, sequência, alcance, linha de interação e limites. Clientes enviam intenções no fluxo de comandos; não enviam transformações oficiais. Estado público sanitizado via world_snapshot; movimento/previsão recebem bloqueadores por instância, nunca numa lista global mutável. Porta inicialmente aberta preserva caminhos antigos; fechamento impede sobreposição com jogador/objeto. Props limitados e restauração por rodada. Morte/desconexão liberam posse.

A extensão de ações e snapshots exige versão12 intencional, documentada, com handshake recusando11 e sem novos métodos RPC para preservar índices do handshake. Não se promete compatibilidade de sessão entre builds11/12. Esta evolução foi autorizada no escopo; a restrição é contra alteração involuntária.

Eventos sonoros partem de ações aceitas e deslocamento oficial, com ids/época/deduplicação/limites; cliente gera PCM nativo e espacializa localmente, sem novos assets. Volumes locais por categoria. Corrida não existe: preserva-se velocidade atual, classificação walk/run preparada sem criar sprint.

Animação procedural existente continua; camada de ações visuais subordinada ao estado oficial, com prioridades/interrupção e timestep independente. Investigação reutiliza BodyRegistry/BodyRules, revela apenas fatos públicos seguros e mensagem privada ao solicitante, sem assassino/autor/inventário. Habilidades indefinidas ficam fora.

Mansão recebe objetos/indicadores a partir das definições oficiais. NPC/diálogo: avaliação documentada sem runtime se não houver necessidade. Otimização mede baseline e fase2 com custos limitados. Integração usa transporte real e quatro/oito clientes, isolamento, segurança e reset.

## Erros e validação

Payload malformado/stale/dead/out-of-range/replay/rate/sem LOS não altera mundo. DTOs públicos com allowlist, nenhum papel secreto. Eventos pertencem à sala/rodada. Reset encerra sons/animações e elimina estado antigo. Tests unitários + suites existentes + multiprocesso + checks remotos; teste não executado é pendência explícita.
