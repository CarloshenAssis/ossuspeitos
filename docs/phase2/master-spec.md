# MISSÃO AUTÔNOMA — SUSPEITOS FASE 2
## MASTER SPEC 09–16 — Física, Áudio, Interações e Investigação Social

**Repositório:** `CarloshenAssis/ossuspeitos`  
**Engine:** Godot 4.4.1  
**Execução:** Codex Cloud  
**Modo:** Desenvolvimento autônomo, testes contínuos e integração em branch isolada.

---

# 0. OBJETIVO DA MISSÃO

Desenvolver os SPECs 09 a 16 do Suspeitos, evoluindo os sistemas atuais para oferecer:

- Física ambiental interativa.
- Portas, objetos e elementos manipuláveis.
- Áudio espacial capaz de fornecer informações sobre ações de outros jogadores.
- Animações e transições mais naturais.
- Interações sociais e investigativas.
- Ambientes mais interessantes.
- Arquitetura preparada para futuros NPCs.
- Desempenho adequado para multiplayer.
- Integração completa com o servidor autoritativo existente.

O resultado deve ser uma evolução funcional e testada do jogo, não apenas uma demonstração técnica.

## Contexto obrigatório

O projeto já passou pelos SPECs 00–08.

Referências:
- PR #30: https://github.com/CarloshenAssis/ossuspeitos/pull/30
- PR #31: https://github.com/CarloshenAssis/ossuspeitos/pull/31

Antes de começar:

1. Verifique o estado atual dos dois PRs.
2. Identifique se a branch `main` já recebeu esses trabalhos.
3. Caso os trabalhos anteriores ainda não tenham sido integrados, use como base o commit final validado do PR #31, desde que continue sendo o commit correto.
4. Não presuma que o código de um PR aberto já existe na `main`.
5. Não faça merge na `main`.
6. Preserve as melhorias já desenvolvidas de movimento, armas, previsão, câmera, gráficos e networking.
7. Leia o relatório final dos SPECs 01–08.
8. Estabeleça uma nova baseline de testes.

Crie uma branch de integração própria:

`codex/gameplay-specs-09-16`

Todos os SPECs deverão ser desenvolvidos e testados dentro dessa linha de trabalho, com commits identificados.

---

# 1. REPOSITÓRIOS DE REFERÊNCIA

Pesquise e documente os seguintes projetos:

1. Godot Jolt  
   https://github.com/godot-jolt/godot-jolt

2. Open 3D Engine  
   https://github.com/o3de/o3de

3. Godot State Charts  
   https://github.com/derkork/godot-statecharts

4. Godot XR Tools  
   https://github.com/GodotVR/godot-xr-tools

5. Dialogue Manager  
   https://github.com/nathanhoad/godot_dialogue_manager

6. Terrain3D  
   https://github.com/TokisanGames/Terrain3D

7. The Dark Mod  
   https://github.com/stgatilov/darkmod_src

8. OpenMW  
   https://github.com/OpenMW/openmw

Para cada projeto, documente:

- Commit consultado.
- Licença do código.
- Licenças de componentes externos e assets.
- Compatibilidade com Godot 4.4.1.
- Recursos aproveitáveis.
- Alternativas nativas do Godot.
- Custos de desempenho e manutenção.
- Decisão: adaptar, reimplementar, estudar ou descartar.

Não instale todos os projetos automaticamente.

Prefira soluções nativas do Godot quando forem suficientes.

Não copie código GPL nem assets sem licença de reutilização confirmada.

---

# SPEC 09 — FÍSICA INTERATIVA

**Referência principal:** Godot Jolt.  
**Referência secundária:** Open 3D Engine.

## Objetivo

Permitir que os jogadores interajam com objetos físicos do cenário.

## Recursos

Implementar progressivamente:

- Portas que abrem e fecham.
- Objetos que podem ser empurrados.
- Objetos leves que podem ser pegos e soltos.
- Colisões com obstáculos.
- Objetos que caem e produzem sons.
- Limites de massa e alcance de interação.
- Estados físicos sincronizados quando relevantes.
- Interações disponíveis apenas para jogadores autorizados.

## Requisitos de arquitetura

Criar ou adaptar componentes equivalentes a:

- `InteractionAuthority`
- `InteractableObject`
- `PhysicsObjectDefinition`
- `PhysicsState`
- `InteractionRequest`

Não criar esses componentes se já existirem equivalentes adequados.

O servidor deve validar:

- Identidade do jogador.
- Estado do jogador.
- Distância até o objeto.
- Visibilidade ou linha de interação quando necessária.
- Disponibilidade do objeto.
- Limite de ações.
- Velocidade e deslocamentos permitidos.

O cliente não pode determinar sozinho uma mudança física que afete regras, bloqueie trajetórias ou modifique o estado compartilhado.

## Estratégia de física

O projeto atual utiliza geometria e colisões determinísticas.

Não substituir essa arquitetura indiscriminadamente.

Comparar Godot Physics e Jolt em uma cena de laboratório.

Objetos puramente decorativos podem usar simulação local. Objetos que bloqueiam jogadores, tiros ou alteram o mundo compartilhado precisam de representação autoritativa consistente.

Não implementar destruição total de cenários nesta etapa.

## Testes

- Porta aberta e fechada em dois clientes.
- Dois jogadores tentando manipular o mesmo objeto.
- Objeto fora do alcance.
- Jogador morto tentando interagir.
- Objeto desconectado ou removido.
- Manipulação sob 200 ms de latência artificial.
- Tentativas de teletransportar objetos.
- Colisão entre objeto e jogador.
- Objeto bloqueando ou não um tiro conforme seu estado autoritativo.
- Comparação entre Godot Physics e Jolt.

## Aceitação

Uma cena multiplayer funcional deve demonstrar interações físicas compartilhadas sem divergências críticas entre clientes.

---

# SPEC 10 — ÁUDIO ESPACIAL E INFORMAÇÃO SONORA

**Referências:** The Dark Mod, Godot AudioStreamPlayer3D e sistemas nativos de áudio.

## Objetivo

Fazer do som uma fonte de informação para os jogadores.

## Recursos

Implementar:

- Passos posicionais.
- Diferença sonora entre caminhada e corrida.
- Sons de portas.
- Sons de objetos caindo.
- Sons de disparos.
- Sons de recarga.
- Atenuação por distância.
- Posicionamento espacial.
- Categorias e prioridades de eventos sonoros.
- Configuração de volumes separados.

## Arquitetura

Criar componentes equivalentes a:

- `SoundEvent`
- `SoundEventCatalog`
- `SpatialAudioController`
- `AudioOcclusionResolver` (somente se viável)

Os sons devem ser reproduzidos localmente a partir de eventos autorizados.

O servidor valida a ocorrência da ação relevante; o cliente renderiza o áudio.

Não transmitir arquivos de áudio continuamente pela rede.

Não permitir que clientes produzam livremente sons globais falsos.

Separar eventos sonoros cosméticos de eventos com relevância competitiva.

## Requisitos adicionais

Quando viável, criar diferenças simples entre:

- Som próximo.
- Som distante.
- Som vindo de outra sala.
- Som com obstáculo entre origem e jogador.

A oclusão avançada deve ser opcional e avaliada por custo.

Não introduzir chat de voz nesta etapa.

## Testes

- Dois jogadores em salas diferentes.
- Sons de passos em distâncias distintas.
- Porta abrindo e fechando.
- Objeto caindo.
- Som de disparo.
- Eventos simultâneos.
- Teste de volume zero.
- Ausência de eventos duplicados.
- Latência e sincronização de eventos.
- Comportamento sem dispositivo de áudio.

## Aceitação

Os jogadores devem receber pistas sonoras consistentes sobre ações ocorridas no ambiente, sem depender de informações que o servidor não autorizou.

---

# SPEC 11 — ANIMAÇÕES E ESTADOS VISUAIS

**Referências:** Godot State Charts, O3DE e recursos nativos de AnimationTree.

## Objetivo

Melhorar a apresentação dos personagens e das interações.

## Recursos

Desenvolver ou aprimorar:

- Idle.
- Walk.
- Run.
- Disparo.
- Recarga.
- Interação com objetos.
- Manipulação de portas.
- Reação a impacto.
- Animação de morte.
- Transições de estado.
- Sincronização visual de personagens remotos.

## Arquitetura

Investigar se Godot State Charts oferece benefícios reais em relação à estrutura atual.

Se for conveniente, utilizá-lo apenas em módulos apropriados.

Preservar os estados oficiais no servidor.

Não permitir que uma máquina de estados visual modifique arbitrariamente regras de partida.

Não substituir todo o sistema de animações procedural por AnimationTree sem justificar a mudança.

Priorizar os modelos existentes e animações programáticas quando suficientes.

## Testes

- Jogador parado.
- Caminhada e corrida.
- Mudança rápida de direção.
- Disparo durante movimento.
- Recarga.
- Morte durante interação.
- Interrupção de animação.
- Reconexão e recuperação de estado visual.
- Estado remoto sob latência.
- Consistência entre 30, 60 e 120 FPS, quando mensurável.

## Aceitação

Os personagens devem representar visualmente suas ações sem alterar a simulação autoritativa.

---

# SPEC 12 — INVESTIGAÇÃO SOCIAL E EVIDÊNCIAS

**Referências conceituais:** Trouble in Terrorist Town, Among Us e Deceit.

**Referência arquitetural complementar:** OpenMW.

## Objetivo

Aprimorar os mecanismos de investigação do Suspeitos, respeitando as regras já definidas.

## Recursos

Avaliar e implementar mecanismos incrementais de:

- Inspeção de corpos.
- Interação com cadáveres.
- Identificação de objetos importantes.
- Registro de eventos investigáveis.
- Informações sobre disparos e ações permitidas.
- Objetos deixados no ambiente.
- Pistas visuais e sonoras.
- Feedback de ações dos papéis existentes.

## Regras

Preservar a lógica de detetive, assassino e vítima.

Não implementar automaticamente habilidades inéditas de papéis.

A mecânica de assassino com arma especial de um único tiro, a punição do detetive por atingir inocentes e a chance de ressurreição foram discutidas anteriormente, mas não estão completamente implementadas no jogo.

Portanto:

1. Registrar essas funcionalidades como regras pendentes de confirmação técnica.
2. Não presumir custos, cooldowns, efeitos ou probabilidades que não estejam definidos de forma inequívoca.
3. Implementar primeiro o mecanismo genérico de interação/investigação compatível com as regras existentes.
4. Isolar as habilidades futuras em especificações próprias.

## Segurança e informação

O servidor deve controlar:

- Quem pode investigar.
- Qual objeto está sendo investigado.
- Qual informação pode ser revelada.
- Quando uma informação pode ser revelada.
- O que permanece oculto até o fim da rodada.

Não expor identidade secreta do assassino por snapshots, logs enviados ao cliente ou efeitos cosméticos não autorizados.

## Testes

- Corpo gerado após morte.
- Corpo inspecionado.
- Dois jogadores inspecionando o mesmo corpo.
- Jogador sem permissão solicitando informação.
- Jogador morto tentando investigar.
- Informação secreta preservada.
- Encerramento da rodada.
- Reconexão e consistência das evidências.

## Aceitação

O sistema deve proporcionar interações investigativas úteis e manter o sigilo e as regras dos papéis.

---

# SPEC 13 — AMBIENTES INTERATIVOS

**Referências:** O3DE, Godot XR Tools, Terrain3D e Godot nativo.

## Objetivo

Aumentar a qualidade das interações da mansão existente.

## Recursos

Adicionar, quando compatível:

- Portas com estados compartilhados.
- Objetos interativos distribuídos no mapa.
- Iluminação ambiental apropriada.
- Sons de ambiente.
- Indicadores discretos de interação.
- Objetos de cenário com colisão.
- Feedback quando uma interação não for permitida.
- Pequenas situações emergentes resultantes das ações dos jogadores.

## Requisitos

Priorizar o mapa oficial da mansão.

Não criar mapa externo grande nesta etapa.

Utilizar Terrain3D apenas como referência e registrar se sua integração faz sentido para mapas futuros.

Evitar adicionar elementos visuais que bloqueiem injustamente a visão de outros jogadores.

Evitar destruir ou substituir a geometria autoritativa.

Garantir que portas e objetos interativos mantenham o mesmo comportamento para o servidor e todos os clientes.

## Testes

- Entrada e saída de ambientes.
- Visibilidade através de portas.
- Interação com portas simultâneas.
- Movimento próximo a obstáculos.
- Compatibilidade com tiro e colisão.
- Desempenho com quatro e oito clientes.
- Reinício de rodada e restauração do cenário.

## Aceitação

A mansão deve oferecer novas possibilidades de interação mantendo gameplay, desempenho e sincronização consistentes.

---

# SPEC 14 — IA, DIÁLOGOS E ARQUITETURA FUTURA

**Referências:** OpenMW, The Dark Mod e Dialogue Manager.

## Objetivo

Preparar uma arquitetura extensível sem criar complexidade desnecessária.

## Escopo

1. Avaliar a necessidade real de NPCs.
2. Documentar opções de máquinas de estados para IA.
3. Identificar mecanismos existentes que possam ser reutilizados.
4. Avaliar diálogos contextuais sem comprometer o multiplayer.
5. Criar protótipos isolados apenas quando apresentarem valor técnico concreto.

## Restrições

Não adicionar NPCs ao modo principal automaticamente.

Não instalar Dialogue Manager sem verificar versão compatível com Godot 4.4.1.

Não utilizar serviços pagos de IA.

Não incorporar sistemas de linguagem generativa em tempo real.

Não criar infraestrutura adicional de servidores para NPCs.

## Testes

Os protótipos opcionais devem estar isolados do jogo principal e não gerar regressões.

## Aceitação

Entregar documentação e, caso seja tecnicamente justificado, componentes experimentais isolados e testados.

Este SPEC pode ser concluído sem alteração no runtime de produção, desde que a avaliação seja devidamente documentada.

---

# SPEC 15 — OTIMIZAÇÃO E COMPATIBILIDADE

## Objetivo

Garantir que os sistemas adicionados não comprometam estabilidade ou desempenho.

## Plataformas

Priorizar:

- Windows.
- Linux para servidor dedicado.
- Web, conforme suporte atual do projeto.

Não presumir certificação de Android, macOS ou GPUs físicas sem testes efetivos.

## Métricas

Medir, quando tecnicamente possível:

- Tempo de frame.
- Tempo de física.
- Carga de CPU.
- Memória.
- Objetos ativos.
- Quantidade de eventos de áudio.
- Dados de rede enviados e recebidos.
- Frequência e tamanho de snapshots.
- Desempenho com quatro clientes.
- Desempenho com oito clientes.

Comparar com o baseline anterior.

## Otimizações

- Limitar objetos interativos ativos.
- Evitar efeitos custosos fora de alcance.
- Reduzir atualizações desnecessárias.
- Controlar frequência de sincronização.
- Evitar replicação de objetos cosméticos sem relevância para gameplay.
- Usar pooling quando justificável.
- Evitar dependências nativas desnecessárias.

## Testes

Executar todos os testes de regressão relevantes.

Não reduzir qualidade dos testes para alcançar desempenho artificialmente.

Não declarar certificação de GPU física com base em Mesa llvmpipe.

## Aceitação

Sem regressões críticas de desempenho, build ou estabilidade. Caso algum recurso seja excessivamente custoso, preservar sua implementação atrás de opção desabilitada por padrão ou retirá-lo da integração.

---

# SPEC 16 — INTEGRAÇÃO E PLAYTEST

## Objetivo

Integrar os SPECs anteriores num conjunto jogável.

## Cenário integrado obrigatório

Criar uma cena ou sequência de teste com:

- Um servidor autoritativo.
- Quatro clientes simultâneos.
- Campanha de oito jogadores.
- Movimento e colisões.
- Portas interativas.
- Objetos físicos.
- Passos e sons posicionais.
- Armas e disparos.
- Reações visuais.
- Corpos investigáveis.
- Reinício de rodada.

## Verificações de segurança

- Sem duplicação de eventos.
- Sem manipulação ilegal de objetos.
- Sem acesso indevido a papéis secretos.
- Sem autoridade de dano no cliente.
- Sem inconsistência entre colisão e tiro.
- Sem regressões dos SPECs 01–08.
- Sem alteração involuntária de protocolo.
- Sem dependências proibidas por licença.

## Testes

Executar:

1. Testes unitários existentes.
2. Testes dos novos componentes.
3. Testes de integração.
4. Testes multiprocesso.
5. Testes de isolamento de salas.
6. Testes adversariais.
7. Testes de reconexão relevantes.
8. Testes de encerramento e limpeza de processos.
9. CI remoto.
10. Builds Web e Windows quando suportados pelo ambiente.
11. Verificação de container de servidor.
12. Smoke test gráfico automatizado quando viável.

Registrar o que não pôde ser testado.

## Entrega

- Branch de integração.
- Commits por SPEC.
- Testes automatizados.
- Relatórios de evidências.
- Matriz de funcionalidades.
- Relatório de desempenho.
- Inventário de licenças.
- Pull Request consolidado.
- Instruções para playtest humano.

---

# 2. POLÍTICA DE AUTONOMIA DO CODEX

Você está autorizado a:

- Estudar os oito projetos externos.
- Desenvolver e refatorar sistemas dentro do escopo.
- Criar scripts, cenas, configurações e testes.
- Executar testes.
- Corrigir falhas.
- Criar commits e branches.
- Fazer push para branches de desenvolvimento.
- Integrar os SPECs na branch de trabalho.
- Criar e atualizar Pull Requests.
- Executar revisões independentes quando disponíveis.
- Avançar automaticamente entre os SPECs 09–16.

Você não precisa pedir aprovação a cada SPEC.

## Proibições

- Não fazer merge na `main`.
- Não publicar no GitHub Pages.
- Não fazer deploy no Railway.
- Não alterar workflows de publicação para contornar restrições.
- Não enfraquecer a proteção de branches.
- Não copiar código incompatível com as licenças.
- Não importar assets sem licença verificada.
- Não substituir o Godot.
- Não modificar sistemas essenciais sem testes de regressão.
- Não implementar funcionalidades de papel ainda indefinidas.
- Não marcar testes não executados como aprovados.
- Não criar custos de infraestrutura externa sem autorização.

---

# 3. ESTRATÉGIA DE EXECUÇÃO

Execute os SPECs 09–16 sequencialmente, integrando os componentes na branch de desenvolvimento.

Para cada SPEC:

1. Auditar o componente atual.
2. Estudar as referências.
3. Escolher a solução mais simples e compatível.
4. Implementar.
5. Testar.
6. Corrigir falhas.
7. Revisar segurança, licenças e desempenho.
8. Registrar resultados.
9. Criar commit.
10. Avançar para a próxima etapa.

Não substituir um sistema existente apenas porque uma referência externa usa outra arquitetura.

Se algum recurso não for viável:

- Documente a causa.
- Preserve o código funcional.
- Evite bloquear os demais SPECs independentes.
- Continue com as etapas compatíveis.
- Registre claramente o recurso não entregue.

---

# 4. CRITÉRIOS DE QUALIDADE

A prioridade é:

1. Correção do gameplay.
2. Integridade do servidor autoritativo.
3. Segurança dos estados e informações.
4. Compatibilidade multiplayer.
5. Estabilidade.
6. Desempenho.
7. Experiência visual e sonora.
8. Extensibilidade.

Não sacrificar os primeiros itens para obter efeitos visuais mais impressionantes.

---

# 5. RELATÓRIO FINAL

Entregar ao finalizar:

- Tabela SPEC 09–16 com status real.
- Arquivos modificados.
- Funcionalidades implementadas.
- Repositórios e commits consultados.
- Licenças de código reutilizado.
- Resultado de cada teste.
- Resultados de CI.
- Métricas comparativas.
- Falhas conhecidas.
- Funcionalidades adiadas.
- Build e instruções de execução.
- Link do PR consolidado.
- Riscos restantes para merge.
- Recomendações da próxima fase.

O relatório deve separar explicitamente funcionalidades implementadas, protótipos experimentais, funcionalidades adiadas e sugestões futuras.

---

# 6. INSTRUÇÃO FINAL

Inicie a execução técnica dos SPECs 09–16 de maneira autônoma.

Não pare após concluir um único SPEC se houver capacidade de continuar.

Priorize código funcional e testes reais, não somente documentação.

Trabalhe somente em branches de desenvolvimento, mantendo a main intacta.

Ao finalizar, entregue um PR consolidado para revisão.

Se o ambiente encerrar a execução antes de concluir todos os SPECs, deixe um handoff preciso, identificando o commit, os testes realizados e o próximo passo. Não declare continuidade automática se ela não estiver efetivamente agendada ou disponível.

**Meta: transformar a mansão do Suspeitos num ambiente multiplayer interativo, com física, áudio, animações e investigação funcionando de maneira integrada.**