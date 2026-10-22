# SPEC 09 — interação física autoritativa

Base: commit validado `59926cb`, Godot 4.4.1. A arquitetura existente usa colisão analítica da mansão (`ArenaRules`, `MovementRules`), hitscan servidor e comandos com época/ACK. Não foi trocada por rigid bodies de engine.

## Implementado no runtime

- `EnvironmentRules`: catálogo imutável e limitado a 20 portas da mansão + três objetos (2, 3 e 10 kg), alcance de 2,5 m e DTO de allowlist sem papéis, inventário ou autoria de morte.
- `InteractionAuthority` por `MatchRoom`: estados, posse exclusiva, IDs de ação monotônicos e intervalo mínimo de 200 ms. Valida participante vivo/rodada, alvo, verbo, alcance, linha de interação, massa e ocupação. Não recebe posição, força, velocidade ou dano do cliente.
- Portas iniciam abertas para preservar rotas originais. Fechar é recusado se jogador ou objeto ocupa a folha. Mesmos AABBs fechados alimentam movimento, hitscan e apresentação. A folha aberta desliza para dentro da parede adjacente, sem folha opaca atravessável no vão.
- Objetos leves podem ser carregados/soltos; o pesado só empurrado. O servidor simula gravidade, velocidade horizontal máxima de 1,5 m/s e queda máxima de 6 m/s. Varredura de transporte em trechos de até 0,15 m impede cruzar porta, objeto, parede ou outro jogador. Soltar em posição ocupada é recusado. Não há lançamento livre nem destruição.
- Desconexão/morte libera posse. Liberação forçada busca posições próximas livres; em ocupação extrema mantém o objeto acima do plano dos jogadores, sem transformá-lo em barreira que prenda alguém. Rodada nova restaura o catálogo.
- O fluxo existente de comandos carrega `interact`; a ação acontece no mesmo ponto causal de mira, com a época/gate já validados. Snapshot carrega `environment` público por sala, instalado na previsão **antes** do replay do ACK. Nenhum estado mutável global é compartilhado entre salas.
- Controles: E abre/fecha porta quando não há arma/munição para coletar; F pega objeto leve; G empurra; Q solta. Prompt discreto informa ações próximas. O servidor continua sendo a autoridade e recusas usam o feedback existente.

## Protocolo deliberadamente alterado

A extensão exige protocolo **12**. Intenção no fio: `["interact", id, object_id, verb]`; verbos limitados a toggle/push/take/drop. Não foram criados RPCs, portanto seus índices de handshake permanecem estáveis. Snapshot tem campo adicional `environment`. Clientes antigos não devem jogar com a nova geometria sem entendê-la; protocolo 11 é recusado explicitamente pelo handshake existente, em vez de ignorar colisões novas. As expectativas Web/container foram atualizadas para a versão 12; nenhuma assertiva foi removida.

## Testes executados

Logs completos: `/workspace/.ossuspeitos-state/phase2/spec09/`.

| Comando (com `$GODOT_BIN` 4.4.1) | Resultado observado |
| --- | --- |
| `--headless --path . --script tests/interaction_authority_test.gd` | OK, 43 verificações |
| `--script tests/movement_rules_test.gd` | MOVEMENT_RULES_TEST_OK |
| `--script tests/netcode_test.gd` | NETCODE_TEST_OK, 266 verificações |
| `--script tests/combat_authority_test.gd` | COMBAT_AUTHORITY_TEST_OK, 86 verificações |
| `bash tests/network_smoke_test.sh` | NETWORK_SMOKE_OK, servidor + 4 clientes, encerramento concluído |
| `bash tests/physics_backend_lab_test.sh` | ambos backends OK, sem erro de engine/script |

O teste novo inclui concorrência de posse, replay/rate limit, jogador morto, alvo ausente, massa, payload de teleporte inválido, DTO sem segredo, cópias independentes, isolamento e reset de salas, colisão de movimento e raio da mesma porta, previsão igual **antes** do ACK e aproximação real até parar na porta, elevar/soltar/cair/empurrar objeto. O RED inicial produziu `INTERACTION_ASSERT interactive authority exists` antes da implementação; logs `red.log` e `extended.log` preservam a evolução.

## Laboratório Godot Physics × Jolt

Cena isolada gerada em diretório temporário, sem importar extensão ou mudar `project.godot` de produção. Uma caixa de 0,5 m cai de 2 m sobre piso plano durante 180 ticks, `--fixed-fps 60`. Ambos satisfazem altura de repouso 0,25±0,04 m e velocidade <0,1 m/s.

| Backend nativo | Y final | Velocidade final | Tempo observado para 180 ticks |
| --- | --- | --- | --- |
| GodotPhysics3D | 0,240003 m | 0,000080 m/s | 5.168 µs |
| Jolt Physics | 0,230000 m | 0 m/s | 31.311 µs |

Medição única, uma caixa, simulação acelerada, host compartilhado; **não** é benchmark de gameplay/GPU nem demonstra superioridade geral de backend. A diferença de repouso mostra por que não se deve replicar blockers competitivos por simulação independente de rigid bodies em cada cliente. Decisão: manter colisão determinística existente e estudar Jolt apenas para decoração ou futura simulação oficial específica.

## Limites desta etapa

Não há destruição, arremesso com força livre, corpo mole, empilhamento físico geral nem migração do movimento planar. Comparação nativa é laboratório, não runtime de produção. O smoke de quatro clientes comprova regressão de transporte, mas não substitui o novo cenário multiprocesso de interação/áudio/investigação do SPEC 16. A validação completa com 200 ms e oito jogadores será registrada nesse cenário integrado, sem presumir resultado.

Correção verificada RED→GREEN: encerrar rodada entre pegar objeto no piso e o primeiro tick de transporte restaura o bloqueador por release_peer. A suíte final passou43checks.
