# Revisão independente — SPEC09

## Escopo imutável

Revisão de `ccdee9c..a35f872` (implementação SPEC09), não do checkout atual em evolução SPEC10. Fontes inspecionadas por `git show`/`git diff`; arquivo separado em `/workspace/phase2-review09`. Autor da revisão não alterou fontes nem testes do checkout de desenvolvimento e não criou commits.

**Resultado: requer duas correções importantes antes de aprovação. Nenhum achado crítico.**

## Important 1 — liberação de posse zera indevidamente a sequência da conexão viva

Local: `server/interaction_authority.gd:116–125`, chamado também por `tick` em `:143–145` quando um objeto carregado fica a mais de REACH do alvo derivado do jogador.

`release_peer` apaga `_last_ids` e `_last_times` junto com a posse. Esse método é usado em liberação forçada durante a mesma conexão/rodada, além de desconexão/morte. O cliente mantém o contador de ações. Se já houve mais de64 interações, toda intenção seguinte é recusada como `sequence_jump` contra o zero restaurado, e a interface normal não recupera até a rodada seguinte. Com contagem menor, IDs antigos podem ser readmitidos pela autoridade após nova época; preservar o estado de sequência também evita essa regressão de replay.

Reprodução executada no arquivo a35f872, Godot4.4.1:

1. Criar MatchRoom ativa com quatro participantes; posicionar jogador1 junto à primeira porta.
2. Executar65 toggles aceitos, IDs1–65 separados por220ms.
3. Reposicionar oficialmente junto ao objeto leve; takeID66 aceito, tick registra holder1.
4. Reposicionar oficialmente a mais de2,5m e executar tick; liberação automática registra holder0.
5. IntençãoID67 resulta `{accepted:false, reason:sequence_jump}`. Nenhum dos65 toggles anteriores foi recusado.

A mesma liberação pode ocorrer quando o alvo de transporte está bloqueado e o jogador se afasta. O problema é o reset da conexão, independentemente de como se chega ao ramo.

Correção recomendada: separar liberação de objetos do descarte de registros da conexão. Liberação automática mantém `_last_ids`/`_last_times`; reset de rodada e remoção definitiva do membro podem apagar os registros explicitamente. Teste de regressão deve executar o ramo automático após contador>64, confirmar que a próxima intenção nova é aceita quando espacialmente válida e que uma antiga continua rejeitada.

Evidência: `/workspace/phase2-review09-probe.log`; script diagnóstico isolado `/workspace/phase2-review09/tests/review09_probe.gd`. Saída observada: `TAKE accepted:true holder=1`, `FORCED_RELEASE holder=0`, `AFTER_RELEASE accepted:false reason:sequence_jump`, `early_failures=0`.

## Important 2 — contrato antigo11 restante quebra o check de container

Local: `tests/container_test.sh:113`, `:114`, `:168`.

O commit altera o protocolo oficial para12 e atualiza somente a expectativa de mismatch `server=12`, mas estas três assertivas ainda exigem `protocol=11`:

- linha de `DEDICATED_READY`;
- linha de `DEDICATED_START` release;
- resultado da sonda após idle.

O servidor dedicado usa `NetworkConfig.PROTOCOL_VERSION`, portanto o check `server-container` falhará contra a imagem correta da Fase2. É uma falha determinística de contrato verificável pela comparação das strings; o container completo não foi executado nesta revisão.

Correção recomendada: atualizar as três expectativas exatas para12, ou derivar uma única variável do contrato versionado sem afrouxar assertivas; executar o check de container real no fechamento. Procurar ocorrências restantes por `rg 'protocol=11|server=11|version=11' tests .github`.

## Verificação independente e observações positivas

- `tests/interaction_authority_test.gd` executado no arquivo a35f872: **INTERACTION_AUTHORITY_TEST_OK checks=43 failures=0**. Esse teste não cobre o contador longo após liberação automática.
- Três origens de props verificadas contra colisão estática: nenhuma sobreposição inicial.
- Protocolo12 é explícito, sem método RPC novo; parser limita verbos/tipos/tamanho e não aceita transformações livres de cliente.
- A autoridade usa identidades derivadas do fluxo de comandos, gate/época oficial e estado por MatchRoom; mudança de bloqueadores é instalada antes do replay do ACK. Não foi encontrada lista global mutável de estado de sala.
- Mesmos AABBs alimentam movimento e raycast; porta aberta desliza para a parede sem folha perpendicular não representada. Fechamento consulta jogadores e props, inclusive carregados.
- Morte/desconexão e fim de rodada liberam objetos; a regressão de blocker na transição ENDED já possui cobertura43 no commit revisado.
- O laboratório Physics/Jolt é isolado, sem GDExtension/dependência importada ou alteração de backend de produção. Seu tempo é apresentado como observação acelerada de um caso, sem alegação de benchmark de física/multiplayer geral.

## Limites da revisão

Não executei CI remoto, container/exportações, comparação de backends nem o futuro cenário09–16 com200ms/8jogadores. Permanecem obrigações de integração, não resultados presumidos. Não revisei fontes SPEC10 em edição, nem transformei avisos históricos de áudio em novos achados. O arquivo de revisão foi importado apenas para registrar classes e executar teste puro; não reivindico importação gráfica certificada desse arquivo.

## Resolução pelo coordenador

Commit `4d0b902`: orçamento de replay/taxa preservado por release_peer; teste45checks reproduziu sequência de65ações → release → id66 recusada antes da correção e aceita depois. Reset de rodada continua limpando os orçamentos. As três expectativas do container foram atualizadas para12, sem remover assertivas; Bash syntax PASS, container completo aguarda execução final/CI. Esta resolução não altera o resultado histórico da revisão imutável nem representa uma segunda revisão independente.
