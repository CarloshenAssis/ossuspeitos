# SPEC10 — áudio espacial

Implementado com código próprio e PCM sintetizado, sem arquivos externos: SoundEventAuthority por sala deriva passos de deslocamento oficial (não teclas/velocidade enviada), porta/impacto de eventos da InteractionAuthority e recarga de resultado aceito. Catálogo/DTO allowlist não inclui papel, autor de morte nem inventário. Ring máximo32eventos, IDs por rodada, snapshot público limitado e cliente deduplicado. Teleporte/época nova, parado e morto não geram passos; não existe sprint, portanto step_run é categoria reservada e não altera velocidade.

SpatialAudioController possui12vozes3D fixas, prioridade de porta/objeto sobre passos, corte a24m e atenuação AudioStreamPlayer3D. Não cria um nó por evento. Reconexão inicializa últimoID sem reproduzir histórico. Recarga do próprio jogador continua privada; evento espacial só toca para observadores. Disparos preservam caminho oficial CombatFx e deduplicação da previsão existentes, sem segundo som global.

Menu Configurações → Volumes da partida separa passos, portas/objetos e combate; o volume geral continua Master. Persistência local, aplicação ao vivo e zero sem voz ativa. Resolver de oclusão simples por AABB implementado/testado, **desabilitado por padrão** até medir custo/validar escuta; não é propagação acústica por portais. Nenhum chat de voz.

## Verificação

RED: sound_event_rules inexistente; após módulos24checks; integraçãoRoom ausente reproduzida RED e corrigida; teste final30checks com menu/persistência/aplicação ao vivo e silêncio. Menu novo inicialmente expôs argumento inválido para formatter do slider; menu_test capturou Parse Error e a correção usa Callable. Runner estrito não aceita marcadorOK acompanhado de erro de script.

- `python3 tests/run_phase2_unit_tests.py --logs /workspace/.ossuspeitos-state/phase2/spec10/all-units`: **39/39 PASS** (37originais+interação+áudio), sem SCRIPT/Parse/engineERROR.
- `TEST_PORT=41310 ... bash tests/network_smoke_test.sh`: servidor+4clientes PASS, shutdown completo.
- `spatial_audio_test.gd`: **30checks**, dispositivoheadless/dummy, distância/obstáculo/mudo/dedup/época/malformado/ring/teleporte/morte/categorias/persistência/vozes fixas.

Logs completos `/workspace/.ossuspeitos-state/phase2/spec10/`. Três avisos ObjectDB antigos continuam nas fixtures conhecidas; a nova suíte de áudio não produziu esses avisos. Testes auditivos humanos e escuta em GPU/dispositivo físico permanecem pendentes. A validação de evento autorizado atravessando transporte real está reservada à integraçãoSPEC16; smoke4 é regressão, não prova completa de todas as novas ações.
