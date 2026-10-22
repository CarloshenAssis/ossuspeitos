# Integração dos SPECs 00–16 e transição de publicação

## Autorização e responsabilidade

A missão autoriza integrar PRs30→31→32 progressivamente, corrigir integração e publicar Pages somente com servidor compatível. O usuário autorizou Railway e depois esclareceu que fará esse deploy manualmente (“VOU TER QUE FAZER NO MANUAL, ESQUECI, IGNORA E SEGUE”). A automação pode continuar a integração de código com Pages retido. Não modificar credenciais, variáveis/serviços externos, testes ou proteções para contornar falhas.

Não existe conector/CLI autenticada/token Railway neste ambiente. `railway.json` informa builder/Dockerfile/draining/restart, mas não prova branch, Auto Deploy, Watch Paths, Wait for CI, PR environments ou SHA ativo. Documentos antigos informam republicação automática de main; isso não é certificação atual do painel. A configuração externa e a execução manual ficam com o operador. Nenhum comando de deploy Railway é parte desta alteração.

## Risco encontrado e correção

O workflow Web anterior publicava após todo push de main e também por dispatch manual sem exigir compatibilidade. O cliente online usa `project.godot` para o endpoint `wss://ossuspeitos-production.up.railway.app`; query fora de localhost não substitui esse endereço. Produção11 e cliente12 não interoperam.

O workflow Web continua construindo, testando e entregando artifacts em PR/main. As três etapas de publicação agora exigem saída positiva de `scripts/pages_release_policy.py`. Ela só permite `workflow_dispatch` de main com `release_sha` integral idêntico ao SHA do evento. Campo vazio é apenas build; push e PR nunca publicam. Não há variável global “liberar tudo” nem alteração de credencial.

Antes do deploy Pages, o mesmo job ainda exige: main atual igual ao SHA aprovado, Godot4.4.1/importação gráfica íntegra e sonda de produção que realmente entre, receba snapshots, termine0 e anuncie o protocolo exato do código. Recusa legível de versão, sala cheia, ausência de tráfego, falha de transporte/script ou timeout bloqueiam publicação. A exceção permissiva da sonda de PR não é usada nesse gate. Falha preserva o último site publicado; build não substitui o Pages por si só.

A liberação é um dispatch necessário para coordenar esta migração, não um novo pedido de aprovação a cada SPEC. Mantê-la fora dos checks automáticos de main evita dependência circular: se Railway aguarda CI, um check de main aguardando o servidor novo impediria o próprio deploy.

## Ordem de integração e validação

1. Acrescentar a trava à preparação do PR30; integrar a branch atualizada nos PRs31 e32 sem alterar gameplay. Validar os três heads por CI; testes de política cobrem contexto/SHA e logs positivos/negativos.
2. Antes de cada merge, reconferir head remoto, todos os checks (incluindo duplicatas), ausência de conflitos e diff. Não ignorar falhas nem comparar apenas nomes iguais de um único run.
3. Integrar30→31→32 na main. Quando o head já recebeu a preparação, comparar o tree candidato de integração com o tree efetivamente validado: mesmo conteúdo pode ter SHA de commit diferente por ancestralidade/metadados. Se conteúdo mudar, validar o novo conteúdo antes de integrar.
4. Após31, base32 vira main; conferir que o diff contém somente Fase2. Preservar versões/licenças/contratos documentados nos PRs; nenhum addon/asset novo é acrescentado por esta correção.
5. Conferir main final, ancestry dos três heads e checks pós-merge. Executar novamente a regressão aplicável ao conteúdo final, mantendo identidades dos artefatos.

## Railway manual e liberação do Pages

O operador deve verificar a configuração real do serviço e atualizar para o SHA final validado de main, com Godot4.4.1 e protocolo12, sem alterar variáveis/serviços desnecessariamente. Manter uma via de rollback para o SHA anterior e seus artifacts.

Não publicar o cliente12 enquanto a sonda estrita não aceitar o servidor12. Após o servidor compatível estar ativo e os checks verdes, executar o workflow Web em main com `release_sha=<SHA final integral>`. O gate fará nova prova de compatibilidade imediatamente antes de publicar. Se ainda houver servidor11, o workflow falha antes do deploy e mantém o site anterior.

Um endpoint único não mantém simultaneamente clientes11 e12: ao trocar o servidor, abas antigas/clientes em cache11 recebem recusa e precisam recarregar/atualizar. Segurar o Pages mantém o cliente11 disponível, mas ele só funciona enquanto o servidor11 continua ativo. Para continuidade das duas versões, é necessário endpoint paralelo11/12 e roteamento/distribuição correspondente, fora desta correção. Sem isso, coordenar a troca com o operador fora de partidas e avisar os jogadores; não prometer ausência de interrupção nem preservação da partida em memória.

## Evidências e encerramento

Os checks históricos estavam verdes nos heads cfe260b (#30),59926cb (#31),b0f70b4 (#32); novos commits exigem novos checks, não herdam aprovação por inferência. Resultados atuais, SHAs de merge e estado de publicação serão registrados na entrega/PRs após observação efetiva.

Testes locais da política executam o programa real em subprocessos, cobrindo sete contextos de release e nove casos de sonda. O teste de formato usa a saída real de NetworkApp (`PROBE_OK ... protocol=N elapsed_ms=N`). Godot/gameplay/transporte continuam sujeitos aos checks existentes. Android/macOS, GPU física, escuta/playtest humano e procedência de assets antigos não são certificados pela integração.

## Correções antecipadas para a primeira integração

A regressão estrita da main anterior encontrou `combat_feedback_test.gd` com quatro erros de look_at fora da árvore e `netcode_test.gd` com nove recursos retidos ao encerrar, embora os scripts antigos imprimissem seus marcadores. Não foram tratados como aprovação. O trecho de tracer já corrigido noPR31 foi antecipado, sem alterar dano/mira; a captura WeakRef do Loop de teste já corrigida noPR31 foi antecipada, eliminando os nove recursos retidos; a factory WeakRef do helper de atraso já corrigida naFase2 também foi antecipada, sem alterar perfis/filas. A regressão de lifecycle copiada da entrega posterior reproduziu8falhas/24checks antes da correção (quatro perfis nessa base), preservando as assertivas; após integrar os perfis de01–08 ela cobre42checks. São as mesmas correções, não implementações duplicadas.

A primeira importação local omitiu o driver Vulkan de software homologado e emitiu erros de extensão; a repetição usa o ambiente fixado da missão e não considera aquela tentativa verde. A sonda nativa local do endpoint público falhou em conexão, portanto não provou protocolo ativo nem prontidão para publicar. A publicação segue retida até sonda real bem-sucedida.

Repetição após os três ajustes:31/31suítes GDScript PASS com gate de zero SCRIPT/Parse/engineERROR, Godot4.4.1. Resultados individuais em integration-evidence/pr30-unit-results.json. A sonda hospedada inicial de protocolo11 também terminou com sucesso; resultado Web/CI e merges são observados separadamente. A revisão independente da política não encontrou problema Important, mas ressalva que sondar não torna a troca entre serviços atômica; não prometer continuidade de abas antigas.
