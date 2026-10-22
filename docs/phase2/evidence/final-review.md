# Revisão independente final — Fase 2

**Resultado: REQUEST CHANGES — um achado Important.** Nenhum achado Critical identificado. Isso é uma decisão sobre o patch abaixo, não certificação de todas as plataformas nem autorização para merge/publicação.

## Identidade e escopo

- BASE: `59926cb74c6861c207ad16f7ad2793ea55bc9995`.
- HEAD congelado: `a8e6db62628ccfbbd8b08d0427eb039767e27cfc`.
- Revisão independente, somente leitura dos fontes; este relatório é a única alteração do revisor no repositório. Nenhum commit, push, merge, deploy ou subagente.
- Lidos: diff completo de runtime em `client/`, `server/` e `shared/`, integrações adjacentes de comandos/rodada/retorno ao menu, novos testes/harnesses/workflow, master spec, design, plano, rulings do progresso, relatórios 09–16 e inventário/evidências de referências/desempenho. Documentos finais ainda em preparação pelo executor não pertencem a este HEAD.
- Ao terminar os testes, `git rev-parse HEAD` permaneceu no SHA acima e `git diff --quiet <HEAD> -- client server shared tests .github/workflows` saiu 0.

## Achados

### Critical

Nenhum identificado.

### Important — recarga remota ignora o mute da categoria de combate

**Localização:** `shared/sound_event_rules.gd:21` e `client/spatial_audio_controller.gd:58`; configuração em `client/arena_view.gd:922`.

`category("reload")` retorna `environment`, e o consumidor espacial escolhe `environment_volume`. A recarga local passa por CombatFx e obedece `combat_volume`. Assim, o mesmo tipo de ação fica em categorias diferentes conforme o ator observado.

**Reprodução efetivamente executada:** criar ArenaView, aplicar MenuSettings com combate=0 e ambiente=1, consumir um evento autorizado `reload` de outro peer a um metro do listener. Resultado: `count=1 category=environment combat_gain=0.0`. Inverter para combate=1 e ambiente=0, enviar o próximo ID: `count=0 combat_gain=1.0`. Log local: `/tmp/phase2-review-audio.log`; sonda: `/tmp/phase2-review-audio.gd`.

**Esperado:** a opção “Combate” controla também a recarga remota; “Portas e objetos” controla portas/objetos. **Atual:** mutar combate deixa a recarga remota audível; mutar portas/objetos silencia essa recarga mesmo com combate ligado. Não afeta autoridade, sigilo ou ocorrência do evento. A classificação final é Important por violar o contrato funcional de categorias/volume zero do SPEC10. A comunicação preliminar do revisor classificou como Minor pelo impacto localizado; a avaliação final considera o mute uma condição de aceitação, independentemente do ator.

**Recomendação:** encaminhar a recarga remota para o ganho de combate, mantendo sua posição 3D e deduplicação. Regressão sugerida: os dois cenários de volumes acima, além da preservação do som de porta quando combate está mudo. Corrigir antes de aprovar a integração; não exige ampliar o escopo de áudio.

### Minor

Nenhum outro achado confirmado.

## Evidência independente executada

Godot oficial `4.4.1.stable.official.49a5bc7b6`, ambiente fixado por `/workspace/.ossuspeitos-state/mission-sdd/env.sh`, fontes do HEAD congelado. Estes resultados foram observados pelo revisor, não inferidos das contagens fornecidas pelo executor.

| Verificação | Resultado |
| --- | --- |
| `tests/interaction_authority_test.gd` | PASS, 45 verificações, 0 falhas |
| `tests/environment_wire_test.gd` | PASS, 23 verificações, 0 falhas |
| `tests/investigation_test.gd` | PASS, 93 verificações, 0 falhas |
| `tests/spatial_audio_test.gd` | PASS, 30 verificações, 0 falhas |
| `tests/character_actions_test.gd` | PASS, 35 verificações, 0 falhas |
| `tests/net_delay_lifecycle_test.gd` | PASS, 42 verificações |
| Novo harness real, 4 clientes/1 rodada/local | PASS, 28 assertivas servidor, 4 marcadores de cliente, shutdown completo |
| Sonda das folhas abertas, 400 pontos por porta | 0 pontos de folha dentro de espaço transitável sem bloqueador estático |
| `git diff --check` limitado a runtime/testes/workflows | PASS |

Nenhuma dessas execuções apresentou SCRIPT ERROR, Parse Error ou linha de engine ERROR. A verificação ampla de whitespace também encontrou CRLF/espaços no master spec fornecido; não há alteração de runtime associada e isso não foi elevado a achado.

Comando do transporte independente:

```sh
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
TEST_PORT=46216 PHASE2_CLIENTS=4 PHASE2_ROUNDS=1 PROFILE=local \
  TEST_LOG_DIR=/tmp/phase2-review-network \
  timeout 210 bash tests/phase2_network_test.sh
```

Logs locais: `/tmp/phase2-review-network/` e `/tmp/phase2-review-network-summary.log`. Marcadores observados: `PHASE2_NETWORK_TEST_OK clients=4 rounds=1 profile=local`, `SERVER_SHUTDOWN_COMPLETE closed=4` e os quatro `CLIENT_SHUTDOWN_COMPLETE`. A sonda geométrica é `/tmp/phase2-review-geometry.gd`. Esses caminhos são evidência desta sessão, não artefatos prometidos de download/CI.

## Avaliação dos focos obrigatórios

1. **Sala/rodada/época e comandos em trânsito:** `interact` percorre o mesmo parse, fila, gate de participação/vida e comparação de época em `AuthoritativeWorld.step` antes de `_run_command_action`. O reset da rodada reinstala os objetos e reinicia a época dos participantes; autoridades pertencem a MatchRoom. Retorno interativo ao menu recarrega a cena inteira, removendo caches locais. A revisão não encontrou um novo caminho que aceite transformações do cliente ou execute interação antes desse gate. O transporte independente executou uma rodada; a campanha de três rodadas/atraso final pertence à matriz do executor, não a esta execução independente.
2. **Concorrência e liberação:** mudança de holder é serializada na autoridade, take recusa holder existente, e morte/desconexão chamam release. O orçamento de IDs/taxa agora sobrevive a release, com regressão de 65+ ações no teste. Disputa por um prop foi exercitada tanto no unitário quanto no transporte real: exatamente um dono.
3. **Privacidade:** ambiente e sons usam contratos explícitos; estado interno de papéis/inventário não é incluído. Inspeção mantém apenas request/round/body/label/condition e a montagem do snapshot consulta `last_for_peer` para cada destinatário. O harness exige respostas somente dos leitores autorizados e ausência nos demais. Papéis especiais indefinidos não foram implementados neste patch.
4. **Geometria:** movimento/previsão/hitscan recebem os mesmos bloqueadores dinâmicos da instância; não há lista mutável global de estado de sala. Porta fechando verifica jogadores e props. O teste real atira e movimenta contra a mesma porta fechada/aberta, verificando dano e passagem; não é apenas chamada de ray helper. A sonda adicional não encontrou folhas abertas opacas em área transitável. A simulação limitada não deve ser descrita como solver rígido geral ou certificação de todas as combinações de contato.
5. **Áudio/visual/lifecycle:** ring de 32 eventos e pool de 12 vozes são limitados, bootstrap marca histórico como consumido, IDs são deduplicados por rodada, ações visuais não escrevem simulação. O caminho de retorno ao menu destrói a cena. A factory estática WeakRef do helper de atraso remove a captura forte anterior; o teste independente de lifecycle passou. Não se afirma teste auditivo humano ou reprodução de toda interrupção real de dispositivo.

## Testes, protocolo, plataformas e limites da conclusão

O novo harness tem barreiras que verificam revisões/objetos recebidos, bloqueadores da previsão, sons autorizados, corpos e respostas individuais. As ações atravessam os RPCs de produção herdados; as posições e armas iniciais são preparação explícita do servidor de teste. Ele complementa os testes antigos; não representa uma partida humana sem fixtures. O runner verifica status, marcador e erros de engine, e os testes anteriores não foram removidos. O wrapper tem teste específico de status de falha e encerramento dos filhos.

Protocolo 12 é uma extensão deliberada de ação/snapshot no mesmo conjunto de RPCs de produção. Catálogo/enum/bitmask são parte da compatibilidade do build. O diff dos scripts Web/container atualiza expectativas de versão preservando as assertivas. O novo workflow tem `contents: read`, testes e upload de logs, sem etapa de Pages, Railway, merge ou publicação. Nenhum workflow antigo de publicação foi alterado por este patch.

Os relatórios de desempenho distinguem bytes Variant estimados de tráfego TCP, workload de modelo de sockets reais e llvmpipe de GPU física. As medições anteriores têm identidade/fingerprint próprios; não equivalem a benchmark repetido no HEAD final. Referências externas são documentadas como estudo, sem novos assets, addons ou bibliotecas na árvore alterada; as pendências de licença dos assets antigos continuam fora desta aprovação.

**Não julgado/certificado independentemente nesta revisão:** resultado de CI remoto ainda em fechamento, builds/exportações Web e Windows, container Docker, Android/macOS, GPU física, rede remota/perda/reordenação, escuta/conforto humano, resolução das licenças antigas e os documentos/commits posteriores a este HEAD. Também não reexecutei toda a matriz de 44 suítes, oito clientes/três rodadas ou RTT200; suas aprovações devem vir dos logs da matriz final do executor. Nenhum desses itens foi convertido em PASS por inferência.
