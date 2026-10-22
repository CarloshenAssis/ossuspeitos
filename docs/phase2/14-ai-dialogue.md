# SPEC14 — avaliação concluída de IA e diálogo

## Necessidade

O modo atual possui quatro a oito pessoas, papéis secretos, rodadas e autoridade de combate. Não há objetivo, roteiro, recursos de navegação ou regra definida que exija NPC. Adicionar um agora aumentaria carga de simulação, superfície de informação e casos de vitória sem fornecer uma função de jogo especificada. A recomendação é não alterar runtime de produção neste SPEC.

## Reutilização e isolamento

MatchRoom já delimita rodada, mundo, inventário, corpos e membros. Um futuro NPC deve pertencer a uma sala e usar decisões no servidor, o mesmo integrador de movimento e as mesmas validações de ação. Nunca simular um cliente dono de dano ou divulgar mapas de papéis à lógica de diálogo. Primeiro especificar se NPC conta como participante, alvo e condição de vitória; não deduzir essas regras.

Uma máquina de estados pequena com enum e transições puras é suficiente para idle/patrulhar/interagir. State Charts agrega estados hierárquicos/paralelos e ferramentas de autoria quando houver estados reais para justificar dependência e sua versão compatível. AnimationTree continua exclusivamente visual. OpenMW e The Dark Mod servem para estudar separação entre percepção, decisão, execução e apresentação; não reutilizar engines/código GPL nem assets.

## Diálogo contextual

Para mensagens de inspeção e recusa, as mensagens locais já existentes e DTO privado de investigação bastam. Um eventual diálogo ramificado deve usar ids de opções allowlisted, validação de contexto/distância/rodada pelo servidor e resultado individual; nunca scripts arbitrários ou dados de papéis secretos no cliente. Não enviar texto gerado por serviço externo nem criar infraestrutura nova.

Dialogue Manager atual exige uma versão de Godot mais recente; a linha compatível deve ser selecionada conforme o inventário de referências antes de qualquer instalação. Não é necessário instalar o plugin para mensagens curtas. A extensão só faria sentido depois de existir roteiro de conteúdo e orçamento de manutenção.

## Opções e custos

| Opção | Uso adequado | Custo/risco |
| --- | --- | --- |
| Enum/RefCounted nativo no servidor | poucos estados determinísticos | escrever transições/testes explicitamente |
| State Charts em módulo isolado | hierarquia/estados paralelos reais | versão, editor, callbacks e manutenção de dependência |
| Dialogue Manager em conteúdo opt-in | roteiro ramificado aprovado | tradução, save/state e validação multiplayer |
| Integração de IA de engine externa | nenhum caso atual | licença, duplicação de runtime e portabilidade; descartada |

Não há protótipo opcional sem valor técnico demonstrável: a autorização permite concluir SPEC14 por avaliação documentada. A avaliação foi conferida contra as APIs09–13: MatchRoom possui InteractionAuthority, SoundEventAuthority e InvestigationAuthority; comandos com época são a única fonte de intenções e DTOs privados de inspeção bastam para o texto contextual. A suíte42/42 permaneceu verde após13; este SPEC altera somente documentação e não cria protótipo ou runtime.

## Compatibilidade confirmada na pesquisa

Inventário completo: references.md. DialogueManager atual4.1.0 exigeGodot4.6+; candidato3.10.5/0049d4d declara4.4+, mas seu projeto de testes não é certificação do plugin no nosso runtime. StateCharts0.22.5/76d226a temMIT e custos próprios de autoria/manutenção, desnecessários para as cinco ações procedurais atuais. OpenMW6901b0a eDarkMod4d04272 são GPL nas fontes consultadas e apenas referências conceituais; nenhum código foi importado.

**Decisão final:** não instalar dependências nem NPCs. Entrega documental válida conforme o próprioSPEC14; nenhuma funcionalidade de IA/diálogo foi declarada implementada. Próxima especificação deve primeiro definir função do NPC, permissões, participação na vitória, percepção permitida e conteúdo de diálogo.
