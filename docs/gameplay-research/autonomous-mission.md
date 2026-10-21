# MISSÃO — EXECUÇÃO AUTÔNOMA DOS SPECS 00–08

Projeto: `CarloshenAssis/ossuspeitos`

Quero que você assuma a execução técnica contínua do plano de evolução do Suspeitos, sem solicitar minha aprovação a cada SPEC.

Estou autorizando o desenvolvimento, a integração em branches de trabalho, a execução de testes, a correção de erros e a abertura de Pull Requests.

## 1. Ponto de partida

O SPEC 00 foi preparado no PR #30:

https://github.com/CarloshenAssis/ossuspeitos/pull/30

Leia integralmente:

- `docs/gameplay-research/master-spec-v1.md`
- `docs/gameplay-research/00-baseline.md`
- `docs/gameplay-research/architecture-contracts.md`
- `docs/gameplay-research/implementation-plan.md`
- `docs/gameplay-research/test-matrix.md`
- `docs/gameplay-research/license-register.md`
- `docs/gameplay-research/spec-automation.md`

Utilize esses documentos como referências de planejamento, mas considere o código atual e os testes executados as fontes definitivas de comportamento.

Aguarde a conclusão dos checks do PR #30 antes de considerar a auditoria validada.

Não é necessário fazer merge do PR #30 na main para iniciar o desenvolvimento: crie uma branch de integração a partir do commit auditado e mantenha o histórico preservado.

## 2. Executar todos os SPECs

Execute sequencialmente:

**SPEC 01 — Movimentação FPS**

Referência: Godot FirstPersonStarter.

Melhore a movimentação existente, aceleração, desaceleração e controles. Não altere automaticamente a simulação vertical ou o protocolo multiplayer.

**SPEC 02 — Prediction e reconciliação**

Referência: Quake III.

Aprimore o sistema existente de predição, replay, reconciliação e interpolação, com testes de latência e comportamento adverso. Não incorpore código GPL.

**SPEC 03 — Framework de combate**

Referência: Red Eclipse.

Melhore a modularidade do combate existente, configurações de armas, disparos e validações autoritativas. Preserve as regras do Suspeitos.

**SPEC 04 — Balística e gunplay**

Referência: Sauerbraten.

Implemente e refine spread, recoil, precisão, trajetória, impactos e feedback, utilizando parâmetros configuráveis e lógica validada pelo servidor.

**SPEC 05 — Câmera e animações**

Referência: Godot TPS Demo.

Aprimore movimentação visual, animações, transições, recuo de câmera e representação de jogadores remotos. Preserve a câmera FPS.

**SPEC 06 — Gráficos e física**

Referência: Wicked Engine.

Use técnicas e algoritmos como referência para melhorar iluminação, materiais, efeitos e física no Godot. Não importe outra engine para o projeto.

**SPEC 07 — Networking**

Referência: ioquake3.

Avalie o transporte, os snapshots, o processamento de comandos, as filas e a sincronização. Otimize o que já existe, sem reescrever a rede desnecessariamente ou copiar código GPL.

**SPEC 08 — Integração final**

Integre os sistemas, elimine conflitos, execute os testes finais e prepare uma versão jogável para revisão.

## 3. Autonomia autorizada

Você pode, sem solicitar novas aprovações:

- Pesquisar e analisar os repositórios de referência.
- Criar branches de trabalho.
- Desenvolver e modificar código.
- Criar e modificar testes.
- Executar testes locais e de integração.
- Corrigir falhas detectadas.
- Refatorar código dentro do escopo.
- Criar commits e fazer push para branches de desenvolvimento.
- Abrir e atualizar PRs.
- Integrar etapas aprovadas pelos testes numa branch exclusiva de integração.
- Avançar automaticamente de um SPEC concluído para o seguinte.
- Atualizar documentação e evidências.

Não interrompa a execução apenas porque uma etapa terminou. Continue automaticamente para a próxima.

## 4. Política de integração

Crie uma branch de integração exclusiva, por exemplo:

`codex/gameplay-specs-01-08`

Desenvolva cada SPEC em commits separados e, quando viável, branches individuais.

Os SPECs devem ser integrados progressivamente na branch de integração, mantendo os commits identificáveis.

**Não faça merge na `main`.**

Não modifique a proteção da `main`, não desative checks e não altere configurações de publicação.

Ao final, abra um PR consolidado da branch de integração contra a `main`.

Se o PR #30 ainda estiver aberto, evite duplicar desnecessariamente os arquivos de auditoria. Documente a dependência entre os PRs.

## 5. Desenvolvimento orientado a testes

Para cada SPEC:

1. Identifique o comportamento atual.
2. Documente a melhoria necessária.
3. Desenvolva a solução.
4. Execute testes unitários.
5. Execute testes de integração.
6. Execute os testes multiprocesso pertinentes.
7. Corrija os problemas encontrados.
8. Faça uma revisão de segurança e consistência.
9. Registre métricas e evidências.
10. Faça commit e avance.

Não considere um SPEC concluído apenas porque o código compila.

Verifique se ele funciona no multiplayer real, dentro das limitações do ambiente.

## 6. Correção automática de falhas

Se encontrar um erro:

- Investigue a causa raiz.
- Corrija o problema.
- Execute novamente os testes afetados.
- Verifique possíveis regressões.
- Documente a correção.

Se encontrar uma incompatibilidade arquitetural, não destrua componentes existentes para contorná-la.

Quando não for possível resolver com segurança, registre o bloqueio, preserve o código funcional e continue com outras tarefas independentes.

Não esconda testes com falha, não enfraqueça asserções para obter sucesso e não declare funcionalidades incompletas como prontas.

## 7. Restrições

Não está autorizado:

- Fazer merge na `main`.
- Publicar no GitHub Pages.
- Fazer deploy no Railway.
- Modificar recursos de produção.
- Apagar branches de terceiros.
- Alterar credenciais.
- Copiar código GPL para dentro do projeto proprietário.
- Incorporar assets sem licença compatível.
- Substituir o Godot por outra engine.
- Reescrever integralmente sistemas funcionais sem justificativa.
- Implementar mudanças de protocolo incompatíveis sem migração e testes.

Qualquer alteração que possa disparar publicação deve ficar fora da branch principal.

## 8. Critérios finais de aceitação

Ao concluir o SPEC 08:

- Projeto Godot funcionando na versão homologada.
- Movimentação FPS integrada ao multiplayer.
- Predição e reconciliação estáveis.
- Sistema de armas funcional e configurável.
- Recoil, spread e feedback de disparos testados.
- Câmera e animações aprimoradas.
- Melhorias gráficas integradas quando compatíveis com o desempenho.
- Networking preservado e validado.
- Regras de partida existentes preservadas.
- Testes multiprocesso concluídos.
- Ausência de regressões críticas conhecidas.
- Inventário de licenças atualizado.
- PR final aberto contra a main.

## 9. Relatório final

Apresente:

1. Resultado de cada SPEC.
2. Funcionalidades realmente implementadas.
3. Referências e licenças utilizadas.
4. Testes executados e resultados.
5. Métricas de desempenho e rede.
6. Arquivos principais modificados.
7. Falhas corrigidas.
8. Pendências ou limitações.
9. Commits e Pull Requests.
10. Instruções para executar e testar o jogo.

## 10. Instrução final

Execute o máximo possível dos SPECs 01–08 nesta tarefa, em sequência, sem depender de novas respostas minhas.

Priorize entregar código funcional, integração e testes, em vez de apenas documentação.

Você tem autonomia para decisões técnicas reversíveis dentro do escopo definido.

Se houver limite de tempo, contexto ou infraestrutura, finalize a etapa atual de forma segura, registre o progresso e produza um handoff preciso para continuação, sem declarar que o trabalho continuará automaticamente caso a execução seja interrompida.

**O objetivo é entregar uma evolução completa e testada do Suspeitos, pronta para revisão e posterior autorização de merge na main.**
