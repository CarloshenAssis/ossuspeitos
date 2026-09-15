# Armed Mystery — instruções do projeto

## Objetivo

Construir um protótipo de FPS social em Godot 4 para 4–8 jogadores, inicialmente para computador e depois Android. Há vítimas, um assassino e um detetive; armas e munições ficam no mapa.

## Regras de arquitetura

- O servidor é autoritativo para papéis, inventário, munição, compras, disparos, dano, morte, ressurreição e vitória.
- Clientes enviam intenções; nunca informam ao servidor que acertaram, mataram, compraram ou venceram.
- Papéis e compras secretas só são enviados ao jogador autorizado.
- Separe regras compartilhadas, cliente e servidor para permitir servidor Godot headless.
- A primeira hospedagem remota é Railway via WebSocket/TCP. Não dependa de APIs exclusivas do Railway; preserve uma futura migração para ENet/UDP em VPS.
- Use gráficos provisórios e priorize uma rodada completa antes de polimento.

## Escopo inicial

- Uma sala, 4–8 jogadores e entrada por endereço/código.
- Movimento FPS, pegar/largar arma, munição, recarga, disparo e morte.
- Um assassino, um detetive e demais vítimas.
- Assassino: arma de um tiro fatal e carta com 33% de ressurreição.
- Detetive: arma de um tiro que mata o assassino; se o alvo for inocente, o atirador morre e o alvo sobrevive.
- Reinício de rodada e condições de vitória.
- Sem voz, contas, ranking, cosméticos ou matchmaking nesta fase.

## Organização esperada

- `client/`: interface, entrada, câmera e apresentação.
- `server/`: autoridade, sessão e validações.
- `shared/`: tipos, constantes e regras determinísticas sem segredos do servidor.
- `tests/`: testes unitários e simulações de partida.
- `docs/`: decisões e instruções operacionais curtas.

## Forma de trabalho

- Comece inspecionando o estado real do repositório.
- Faça alterações pequenas e verificáveis; não reestruture áreas alheias.
- Use subagentes para pesquisas, revisões e testes independentes. Evite edições paralelas nos mesmos arquivos.
- Registre decisões arquiteturais relevantes em `docs/decisions.md`.
- Nunca faça deploy, gere cobrança, altere DNS ou publique builds sem autorização explícita.

## Conclusão de uma tarefa

- Execute os testes relevantes e relate o resultado real.
- Para rede, teste pelo menos servidor + 4 clientes simulados quando a infraestrutura existir.
- Para Android, confirme que a exportação ainda compila quando o SDK estiver configurado.
- Liste limitações conhecidas sem declarar como pronto algo não testado.

