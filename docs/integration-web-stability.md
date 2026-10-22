# Transições Web: backlog e expiração de efeitos

A execução pós-merge [39720577174](https://github.com/CarloshenAssis/ossuspeitos/actions/runs/39720577174) falhou no Chromium mesmo com o servidor e clientes nativos chegando ao resultado/reset. O log Web registrou pausas de renderização de 1973/1768 ms, `Buffer payload full! Dropping data.`, cinco erros de captura de Node liberado e timeout esperando sala lobby/result=true. A correção de importação do PR #33 não corrige esses erros de runtime. Uma execução posterior verde também não prova sua eliminação.

## Fila do cliente

WebSocketMultiplayerPeer usava o limite de entrada padrão 65535 B. No navegador, eventos JS recebem pacotes enquanto o jogo deixa de fazer poll. A fixture exporta um projeto mínimo Godot 4.4.1 que usa o transport de produção, conecta apenas ao servidor local, pausa poll por 3200 ms e recebe 50 pacotes de 3332 B a 20 Hz, seguidos de mensagem de controle. O Chromium sem correção recebeu 19/50, apesar de receber o controle final, e emitiu overflow. Isso reproduz perda real, sem atribuir toda a falha histórica a uma mensagem específica que não foi capturada.

O transport configura entrada em 524287 B antes de conectar. O orçamento é finito: seis segundos do payload medido de oito ativos (3332×20×6=399840B), com margem para overhead/controle; não é garantia de suportar pausas arbitrárias nem benchmark de tráfego TCP. O wrapper é compartilhado por clientes nativos/Web. Servidor, saída, limite de quantidade de pacotes, RPCs, DTOs, autoridade e protocolo 12 ficam iguais. Não se descarta a validação para esconder overflow.

A fixture Chromium entra no workflow Web antes da rodada completa. Ela exige 50/50 snapshots, mensagem final, ausência de erros e encerramento do servidor. O teste nativo preliminar passou com os limites antigos; por diferenças de recepção/backpressure, não foi aceito como reprodução RED do navegador.

## Efeitos e timers

SceneTreeTimer pode sobreviver a clear() ou ao proprietário dos efeitos. GDScript resolve a captura de um Node liberado antes de executar o corpo da lambda; is_instance_valid dentro dela chega tarde. CombatFx captura somente WeakRef, resolve o alvo no callback e mantém a expiração normal.

A regressão usa os quatro efeitos públicos, incluindo controle positivo de expiração, limpeza antecipada e exclusão do proprietário. Antes da correção, imprimiu marcador positivo e exit0, mas 16 erros do motor fizeram o gate estrito falhar. Depois, 29 checks passaram sem erros/avisos. Por isso o browser e o shell agora reprovam ERROR do motor além de SCRIPT ERROR/PAGE_ERROR.

## Publicação

Este ajuste não publica nem altera infraestrutura. Pages continua exigindo SHA integral atual e sonda estrita de protocolo/snapshots; Railway fica sob operação manual do usuário. Cliente 12 não será publicado contra servidor 11. Playtest humano, hardware real e pausas maiores que o orçamento continuam necessários.

## Resultado reproduzível

A fixture Web passou com a correção: 50/50 snapshots e controle final, entrada 524287 B, zero erros (run 39724468247, check 119645119396). A execução RED foi 39724298477/check119644583853 com entrada 65535 B e 19/50. A regressão lifecycle passou 29 checks; a matriz após esse ajuste passou 45/45 suítes. O novo head combinado ainda exige todos os checks antes de merge. Dados: [web-stability-regressions.json](integration-evidence/web-stability-regressions.json). Esses resultados são das regressões delimitadas, não certificação de desempenho em hardware/produção.

A matriz local do conjunto final passou 45/45 suítes com gate estrito após importação gráfica completa (exit0, zero erros). A primeira tentativa do checkout raiz usou cache antigo de classes e foi interrompida; não é contabilizada como PASS. Os resultados das worktrees independentes foram obtidos após importação completa.
