# SUSPEITOS — MASTER SPEC PARA CODEX CLOUD

**Versão:** 1.0\
**Motor-alvo:** Godot 4.x, preservar versão efetiva do repositório\
**Execução:** Codex Cloud, por etapa e branch\
**Objetivo:** aprimorar o FPS multiplayer Suspeitos utilizando projetos open source como referências técnicas, sem substituir o projeto existente.

## Regras gerais de implementação

1. Inspecionar o repositório antes de modificar qualquer arquivo.
2. Preservar funcionalidades, contratos de rede, regras de partida e testes existentes.
3. Preservar servidor autoritativo, identificação de jogadores e validação de comandos.
4. Não importar uma engine completa para dentro do Godot.
5. Preferir componentes modulares, configuráveis e testáveis.
6. Verificar licença, versão e autoria de qualquer código reutilizado. Registrar URL, commit, caminho original, licença e modificação.
7. Não incorporar código GPL de Quake III ou ioquake3. Estudar sua arquitetura e criar implementações independentes.
8. Não importar assets de jogos ou repositórios sem verificação individual da licença.
9. Nunca alterar a branch principal diretamente.
10. Não modificar protocolos persistidos, snapshots ou contratos de rede sem identificar e atualizar todos os consumidores.
11. Não inventar resultado de teste. Informar quais testes rodaram, quais falharam e quais não puderam ser executados.
12. Parar a integração de uma etapa se houver regressão crítica, conflito arquitetural ou licença não verificada.
13. Cada etapa deve produzir código, documentação, testes e relatório de evidências.
14. Usar PRs separados e deixar merge e deploy sujeitos a aprovação.
15. Não ampliar o escopo para novas regras sociais, inventário complexo ou funcionalidades não solicitadas.

---

# SPEC 00 — AUDITORIA E BASELINE

**Referência:** projeto atual Suspeitos.\
**Prioridade:** bloqueadora de todas as etapas.\
**Objetivo:** criar um mapa confiável do estado atual.

## Tarefas

- Identificar a versão do Godot e a estrutura de diretórios.
- Localizar as cenas principais, scripts de jogador, câmera, armas, rede e servidor.
- Identificar input mapping, física, collision layers, tick de simulação e frequência dos snapshots.
- Identificar protocolos e serialização de mensagens, regras de autoridade e estados do jogador.
- Identificar testes existentes, comandos de execução headless, CI e cenários multiprocesso.
- Identificar módulos em produção, protótipos, recursos incompletos e código morto.
- Criar um inventário das interfaces que as etapas seguintes precisam respeitar.
- Executar testes existentes sem alterar a implementação.
- Verificar possíveis riscos de compatibilidade Godot/GDScript e runtime do servidor.

## Entregáveis

- `docs/gameplay-research/00-baseline.md`
- `docs/gameplay-research/architecture-contracts.md`
- `docs/gameplay-research/test-matrix.md`
- `docs/gameplay-research/license-register.md`
- Relatório dos testes iniciais.

## Critérios de aceitação

- Arquitetura existente documentada.
- Baseline de testes estabelecido.
- Nenhuma funcionalidade de produção alterada.
- Contratos críticos identificados antes das próximas implementações.

---

# SPEC 01 — FPS MOVEMENT CONTROLLER

**Referência:** https://github.com/Whimfoome/godot-FirstPersonStarter\
**Licença:** MIT, sujeita à verificação dos arquivos usados.\
**Objetivo:** aprimorar a movimentação FPS com controles responsivos e parâmetros configuráveis.

## Escopo

Desenvolver ou aprimorar:

- Movimentação WASD e normalização diagonal.
- Aceleração e desaceleração no solo.
- Controle limitado de movimento no ar.
- Gravidade e salto, respeitando as regras atuais.
- Sprint configurável.
- Tratamento de rampas e superfícies inclinadas.
- Controle de colisão com paredes e obstáculos.
- Transições de movimento sem mudanças bruscas.
- Parâmetros de velocidade, fricção, aceleração e salto exportados para configuração.

## Instruções ao Codex

1. Ler a implementação FirstPersonStarter e identificar os componentes relevantes.
2. Comparar sua lógica com o movimento existente no Suspeitos.
3. Não substituir o controlador atual sem demonstrar compatibilidade.
4. Adaptar apenas código permitido pela licença e compatível com a versão Godot utilizada.
5. Separar a lógica física de movimento dos efeitos visuais da câmera.
6. Preservar a capacidade de reproduzir movimentos usando entradas de simulação.
7. Manter todos os limites de velocidade definidos ou autorizados pelo servidor.
8. Não adicionar movimentos novos, como wall-running, sliding ou bunnyhop, sem aprovação específica.

## Componentes sugeridos

- `MovementConfig`
- `MovementController`
- `MovementState`

Utilizar nomes existentes se o projeto já tiver equivalentes.

## Testes

- Movimento nos quatro eixos.
- Movimento diagonal sem ganho indevido de velocidade.
- Parada e desaceleração.
- Sprint e retorno à caminhada.
- Salto e aterrissagem.
- Colisão e rampas.
- Velocidade máxima sob entradas contínuas.
- Validação de parâmetros no servidor.

## Critério de conclusão

O personagem apresenta movimentação FPS responsiva, configurável e reproduzível, sem comprometer a validação autoritativa nem causar regressões no multiplayer.

---

# SPEC 02 — MOVIMENTO MULTIPLAYER E PREDICTION

**Referência:** https://github.com/id-Software/Quake-III-Arena\
**Licença:** GPL-2.0 — estudo conceitual, sem incorporação de código.\
**Objetivo:** melhorar a resposta do movimento em partidas online sem perder a autoridade do servidor.

## Escopo

Analisar e, se necessário, implementar:

- Sequenciamento de comandos de input.
- Predição local do movimento do jogador.
- Processamento autoritativo no servidor.
- Reconciliação usando confirmação de inputs.
- Interpolação de jogadores remotos.
- Correção de divergências.
- Tratamento de pacotes atrasados.
- Proteções contra velocidade e teletransporte inválidos.

## Instruções ao Codex

1. Inspecionar a arquitetura do Quake III como referência.
2. Documentar os conceitos de `usercmd`, predição e snapshots com linguagem independente.
3. Não traduzir nem copiar funções GPL.
4. Comparar o funcionamento com o networking já implementado no Suspeitos.
5. Implementar apenas os recursos ausentes que resolvam problemas concretos.
6. Manter a simulação autoritativa como fonte definitiva do estado.
7. Não aceitar posição, velocidade ou resultado de colisão declarados livremente pelo cliente.
8. Evitar teletransportes visíveis durante reconciliação normal.
9. Definir limites de buffers, retries, correção acumulada e descarte de comandos obsoletos.
10. Evitar dependências temporais que prejudiquem repetibilidade dos testes.

## Interfaces sugeridas

- `InputCommand`
- `PredictionBuffer`
- `ReconciliationController`
- `RemoteInterpolation`

## Testes

Executar cenários de:

- Latência artificial de 0, 50, 100 e 200 ms.
- Jitter controlado.
- Perda de pacotes.
- Inputs duplicados.
- Inputs fora de ordem.
- Desconexão e reconexão, se existentes.
- Tentativas de aumentar velocidade indevidamente.
- Comparação entre posição prevista e autoritativa.

As métricas devem ser registradas antes e depois. Não definir sucesso apenas por ausência de erros.

## Critério de conclusão

O jogador local tem resposta adequada, jogadores remotos apresentam movimento estável e o servidor continua rejeitando estados inválidos.

---

# SPEC 03 — FRAMEWORK DE COMBATE FPS

**Referência:** https://github.com/redeclipse/base\
**Licença:** código principal zlib; verificar arquivos e dependências.\
**Objetivo:** construir um sistema de combate modular e adequado às regras do Suspeitos.

## Escopo

- Definições configuráveis de armas.
- Disparo hitscan.
- Suporte arquitetural a projéteis quando necessário.
- Fire rate e cooldown.
- Raycast e colisão.
- Dano e identificação de alvo.
- Eventos de disparo e impacto.
- Gerenciamento de munição.
- Integração com estados de jogador.
- Efeitos de disparo desacoplados da lógica de dano.

## Instruções ao Codex

1. Estudar a estrutura de armas e combate de Red Eclipse.
2. Identificar componentes reutilizáveis sob licença compatível.
3. Priorizar simplicidade, modularidade e desempenho.
4. Preservar os sistemas de tiro já existentes, reaproveitando seus testes e contratos quando possível.
5. Garantir que o cliente envie intenção de disparo, não resultado definitivo de dano.
6. Validar no servidor arma equipada, estado do jogador, cooldown, munição e regras aplicáveis.
7. Manter o resultado do disparo autoritativo.
8. Diferenciar dano físico da aplicação das regras de papéis.
9. Preparar o framework para diferentes armas sem criar todas imediatamente.
10. Não importar mapas, texturas, sons, personagens ou modelos do Red Eclipse.

## Componentes sugeridos

- `WeaponDefinition`
- `WeaponController`
- `FireRequest`
- `HitResolver`
- `DamageResolver`
- `CombatEvent`

## Testes

- Disparo válido.
- Disparo sem munição.
- Disparo durante cooldown.
- Alvo atrás de obstáculo.
- Jogador morto tentando disparar.
- Comandos duplicados.
- Jogador tentando utilizar arma indisponível.
- Dois jogadores atirando simultaneamente.
- Verificação de consistência do dano.
- Aplicação das regras de detetive, assassino e vítima.

## Critério de conclusão

Sistema de armas extensível, com decisões de combate controladas pelo servidor e integração comprovada às regras do Suspeitos.

---

# SPEC 04 — BALÍSTICA E GUNPLAY

**Referência:** https://github.com/jspjut/cube2\
**Licença:** zlib para o código do motor, com verificação individual.\
**Objetivo:** tornar os disparos consistentes, configuráveis e agradáveis de utilizar.

## Escopo

- Spread.
- Recoil lógico.
- Recoil visual desacoplado.
- Precisão no primeiro disparo.
- Precisão durante movimentação.
- Distância e alcance máximo.
- Tipos de disparo previstos nas regras.
- Velocidade de projéteis, caso sejam usados.
- Impacto em diferentes superfícies.
- Eventos para efeitos visuais e sonoros.

## Instruções ao Codex

1. Analisar as soluções de armas de Sauerbraten.
2. Comparar com o framework implementado na etapa 03.
3. Criar um modelo de configuração de arma sem duplicar a responsabilidade do `WeaponController`.
4. Para dispersão aleatória, usar geração reproduzível e controlada pelo servidor.
5. Nunca confiar num seed ou resultado de tiro arbitrariamente escolhido pelo cliente.
6. Separar spread físico, recoil de gameplay e recoil meramente visual.
7. Não implementar penetração complexa, destruição avançada ou física balística custosa sem necessidade.
8. Garantir que armas especiais respeitem as regras de papel e disponibilidade.

## Entregáveis

- Configurações de armas.
- Resolver de trajetória ou hitscan.
- Sistema de recoil/spread integrado.
- Cena de teste de tiros com obstáculos e diferentes distâncias.
- Testes automatizados e documentação de calibração.

## Testes

- Trajetória repetível.
- Distância máxima.
- Obstruções.
- Recoil e recuperação.
- Precisão em movimento.
- Diferença entre tiro visual e resultado autoritativo.
- Reprodução do resultado de disparos em clientes diferentes.

## Critério de conclusão

Os tiros apresentam comportamento determinável no servidor, feedback consistente no cliente e são configuráveis sem alterar a infraestrutura de combate.

---

# SPEC 05 — CÂMERA, MIRA E ANIMAÇÕES

**Referência:** https://github.com/godotengine/tps-demo\
**Licença:** MIT para código; assets com condições próprias.\
**Objetivo:** aprimorar a apresentação visual do jogador e das armas mantendo a jogabilidade FPS.

## Escopo

- Camera controller.
- Suavização visual adequada.
- Transições entre movimento e repouso.
- Recoil visual.
- Head bob moderado e configurável.
- Weapon sway.
- Transição ADS, quando compatível com as armas.
- Animações de idle, caminhada, corrida e disparo.
- Organização de AnimationTree e estados de animação, se aplicável.
- Representação adequada de jogadores remotos.
- Separação entre primeira pessoa local e avatar visto por terceiros.

## Instruções ao Codex

1. Estudar organização de câmera e animação do TPS Demo.
2. Adaptar conceitos de animação para o FPS Suspeitos.
3. Não converter o jogo para terceira pessoa.
4. Preservar a direção de mira utilizada na lógica autoritativa.
5. Garantir que bob, sway e recoil visual não alterem indevidamente o raycast do servidor.
6. Evitar que o cliente remoto tenha acesso a informações visuais não autorizadas.
7. Garantir que animações de jogador morto ou incapacitado correspondam ao estado recebido do servidor.
8. Usar placeholders próprios quando não houver assets aprovados.

## Testes

- Rotação vertical e horizontal.
- Transições rápidas de direção.
- Disparo com recoil.
- Aterrissagem.
- Jogador parado e em movimento.
- Sincronização visual de avatar remoto.
- Mudança para estado DOWNED ou DEAD.
- Ausência de interferência visual no cálculo autoritativo de disparo.
- Tolerância a diferentes taxas de quadros.

## Critério de conclusão

A apresentação FPS ganha qualidade sem alterar a física, as decisões do servidor ou a câmera competitiva de maneira prejudicial.

---

# SPEC 06 — GRÁFICOS, ILUMINAÇÃO E FÍSICA

**Referência:** https://github.com/turanszkij/WickedEngine\
**Licença:** MIT no projeto principal; analisar dependências e componentes.\
**Objetivo:** aplicar técnicas modernas de renderização e física usando os recursos adequados do Godot.

## Escopo

- Materiais PBR.
- Iluminação e sombras.
- Configuração de ambiente.
- Pós-processamento moderado.
- Efeitos de impacto.
- Partículas de disparo.
- Objetos físicos interativos.
- Colisões consistentes.
- Suporte a iluminação apropriada para mapas internos.
- Perfis gráficos configuráveis.
- Métricas de desempenho.

## Instruções ao Codex

1. Usar Wicked Engine como referência de técnicas, não como substituto do renderer Godot.
2. Identificar recursos equivalentes e suportados pela versão do Godot utilizada.
3. Implementar primeiro uma cena pequena de benchmark.
4. Comparar qualidade visual e desempenho com o baseline.
5. Não integrar o runtime completo do Wicked Engine.
6. Não introduzir dependências nativas ou plugins C++ sem justificar necessidade e compatibilidade.
7. Usar a física padrão do Godot, salvo aprovação fundamentada para mudança.
8. Separar simulação física relevante ao gameplay de efeitos puramente visuais.
9. Objetos que afetem colisão ou regras multiplayer devem ter autoridade de estado definida.
10. Evitar que efeitos gráficos alterem a legibilidade de alvos e a visibilidade necessária ao gameplay.

## Testes

- Compatibilidade de materiais.
- Luzes e sombras.
- Impactos em superfícies.
- Objetos móveis com colisão.
- Consistência física sob diferentes FPS.
- Reprodução em duas ou mais instâncias.
- Utilização de CPU e GPU, quando for possível medir.
- Comparação de frame time antes e depois.

## Critério de conclusão

O Suspeitos ganha melhorias visuais perceptíveis e física adequada ao gameplay sem perda de estabilidade multiplayer nem regressões de desempenho inaceitáveis.

---

# SPEC 07 — NETWORKING AVANÇADO

**Referência:** https://github.com/ioquake/ioq3\
**Licença:** GPL-2.0 — estudo conceitual, sem incorporar código.\
**Objetivo:** avaliar e aprimorar a infraestrutura multiplayer do Suspeitos sem reescrever desnecessariamente o servidor existente.

## Escopo

- Estado autoritativo de jogadores.
- Frequência e conteúdo de snapshots.
- Interpolação e reconciliação.
- Priorização de eventos.
- Sequenciamento de mensagens.
- Tratamento de comandos duplicados.
- Descarte de mensagens antigas.
- Eventos confiáveis versus estados transitórios.
- Redução de dados enviados quando apropriado.
- Instrumentação de latência, jitter e perda.
- Segurança das mensagens e validação de origem.

## Instruções ao Codex

1. Inspecionar os mecanismos equivalentes do ioquake3.
2. Criar um relatório de diferenças em relação à arquitetura do Suspeitos.
3. Preservar o protocolo e transporte atuais por padrão.
4. Não converter automaticamente WebSocket/TCP para ENet/UDP.
5. Caso existam ganhos potenciais de ENet, registrar uma proposta separada com benchmark, custos de infraestrutura e plano de migração.
6. Manter a camada de transporte desacoplada da lógica de jogo.
7. Evitar reimplementar a predição criada na etapa 02.
8. Verificar limites de memória e filas de mensagens.
9. Preservar os estados ALIVE, DOWNED, DEAD e LEFT ou seus equivalentes efetivamente implementados.
10. Não introduzir dessintonia entre servidor e clientes.

## Testes

- Um servidor e quatro clientes.
- Entrada e saída de jogadores.
- Sincronização de estado.
- Disparos simultâneos.
- Eventos duplicados e atrasados.
- Pacotes fora de ordem, quando aplicável.
- Latência, jitter e perda artificial.
- Cliente malicioso enviando inputs inválidos.
- Encerramento autorizado do servidor.
- Regressão dos testes multiprocesso existentes.

## Critério de conclusão

A rede permanece compatível com a arquitetura atual e apresenta métricas documentadas de estabilidade, consistência e desempenho. Qualquer migração de transporte fica em PR e decisão separados.

---

# SPEC 08 — INTEGRAÇÃO E CERTIFICAÇÃO DE GAMEPLAY

**Referências:** todos os módulos previamente aprovados.\
**Objetivo:** transformar componentes isolados em uma experiência multiplayer completa e estável.

## Escopo

- Movimento + câmera.
- Movimento + predição.
- Armas + recoil + animação.
- Disparos + validação autoritativa.
- Dano + regras dos papéis.
- Estados de jogador + animações.
- Colisão + sincronização.
- Áudio e feedback, onde já houver recursos autorizados.
- Qualidade visual e estabilidade.
- Regressão completa da partida.

## Tarefas

1. Criar uma cena de testes integrada, sem substituir mapas de produção.
2. Validar o fluxo completo entre lobby, início da rodada, movimentação, combate e encerramento.
3. Confirmar que as regras próprias do Suspeitos continuam intactas.
4. Testar múltiplos clientes e servidor headless.
5. Medir latência, correções de posição, frequência de snapshots e desempenho.
6. Inspecionar conflitos entre controlador de movimento, câmera, animações e networking.
7. Eliminar código duplicado e interfaces não utilizadas.
8. Revisar licenças e atribuições.
9. Atualizar documentação de arquitetura.
10. Produzir um relatório final com funcionalidades implementadas, pendências e possíveis melhorias futuras.

## Cenários mínimos de aceitação

- Partida multiplayer com quatro clientes.
- Movimentação simultânea.
- Colisões corretas.
- Armas com cadência e munição corretas.
- Servidor rejeitando disparos inválidos.
- Detetive atingindo assassino.
- Detetive atingindo inocente e sofrendo a consequência prevista nas regras.
- Assassino utilizando a arma especial conforme as regras atuais.
- Estados de morte/incapacitação consistentes.
- Encerramento e reinício de rodada sem divergências.
- Ausência de erros críticos e regressões de CI.

## Critério de conclusão

O projeto possui uma versão integrada e testada, com evidências suficientes para uma revisão humana antes do merge final.

---

# PROTOCOLO DE ENTREGA DO CODEX

Ao final de cada SPEC, entregar:

1. **Resumo:** o que foi efetivamente desenvolvido.
2. **Referências:** repositórios, commits e arquivos estudados.
3. **Licenças:** origem e licença de qualquer código reutilizado.
4. **Alterações:** arquivos criados ou modificados e razão de cada alteração.
5. **Testes:** comandos, resultados e evidências verificáveis.
6. **Comparação:** baseline anterior versus implementação atual, quando houver métricas.
7. **Compatibilidade:** mudanças em interfaces ou protocolos.
8. **Pendências:** limitações, testes não executados e problemas conhecidos.
9. **Git:** branch, commit e link do PR.
10. **Status:** aprovado tecnicamente, bloqueado ou aguardando revisão.

**Regra final:** não marcar uma etapa como concluída sem demonstrar que funciona integrada à arquitetura do Suspeitos. Nunca fazer merge ou deploy na main automaticamente.
