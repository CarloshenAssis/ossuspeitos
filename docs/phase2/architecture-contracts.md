# Contratos da Fase 2

| Responsabilidade | Implementação | Dados permitidos / limites |
| --- | --- | --- |
| Definição física compartilhada | EnvironmentRules |20portas derivadas deMansionMap+3props; geometria/massa imutáveis no build |
| PhysicsState / InteractableObject equivalente | objetos da InteractionAuthority |id,position,velocity,open,holder; até24; sem transform livre do cliente |
| InteractionRequest equivalente | açãoNetSyncinteract |idmonotônico,object_id≤64,verballowlist; um comando/tick, época/filas/gate existentes |
| Autoridade de interação | uma porMatchRoom |alcance2.5m,massa4kg,200ms,LOS,ocupação,posse,sweepcarry; reset por rodada |
| Movimento/tiro/previsão | World/MovementRules/CombatAuthority/PlayerPrediction |AABBsporinstância, sem lista global mutável; mesmos volumes dinâmicos |
| SoundEvent / catálogo | SoundEventRules/Authority |ações aceitas/deslocamento oficial;32eventos; sem segredo/arquivo remoto |
| Áudio espacial | SpatialAudioController + CombatFx existente |12vozes novas fixas, corte24m,categorias; disparo oficial mantém dedup anterior |
| Animação | CharacterActionState/Animator + ArenaView |somente pivôs/modelo, prioridade/interrupção e envelopes por tempo; nunca root oficial/dano |
| Evidência / investigação | BodyRegistry existente + InvestigationAuthority |corpo oficial, gate e resposta individual allowlist5campos; sem papel/arma/autor |
| IA/diálogo | avaliação documental |nenhumNPC/plugin/serviço externo no runtime |

## Protocolo12 intencional

MétodosRPC existentes mantidos, sem novoRPC de produção. Actioninteract no formato `["interact",id,object_id,verb]`, verbos toggle/push/take/drop/inspect; alvo de corpo canônico `body:<id>`. Portas/objetos/inspeção compartilham o mesmo orçamento de sequência/taxa; liberação forçada não zera conexão viva.

`world_snapshot` conserva tick/session/players/ack e adiciona environment, sounds, inspection:

- environment no fio: `[round_id,revision,closed_door_bits,[[propPosition,propVelocity,holder]×3]]`;
- sounds no fio: `[round_id,first_contiguous_id,[[kind_index,position,peer_id]×≤32]]`, ou[] vazio;
- inspection: DTO privado `{request_id,round_id,body_id,label,condition}` ou{}.

Decoders validam tipo/tamanho/bits/finitude/limites antes de devolver DTOs públicos exatos, sem segredos. Catálogo e ordem de enum são parte da versão do build; mudanças futuras exigem versionamento explícito, não alteração independente do cliente. Codificação pública ocorre uma vez por sala/snapshot; ACK e inspeção são calculados por destinatário. Intervalos60Hz/20Hz e limites anteriores não mudam.

Cliente instala bloqueadores antes do replay doACK. Snapshot de sessão/tick antigo continua recusado. Reset/época descarta ações em trânsito conforme o contrato anterior; nova rodada restaura ambiente, limpa investigação/eventos e poses. Sair de sala/desconectar libera posse; o cadáver oficial mantém a política preexistente. Nenhuma mensagem nova identifica assassino ou concede dano ao cliente.

## Integração

Branch09–16 parte de59926cb, final validado doPR31. PRs30/31 não foram presumidos presentes na main. O PR desta fase deve ser revisado sobre a branch01–08 enquanto oPR31 estiver aberto; para futura integração na main, preservar essa dependência/ancestralidade. Não houve merge, auto-merge, deploy, alteração de proteções ou workflows de publicação.
