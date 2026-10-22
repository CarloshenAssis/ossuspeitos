# SPEC12 — contrato de investigação

Reutilizar BodyRegistry/BodyRules; não gerar cadáver paralelo. Nova intenção é interact(id, "body:<body_id>", "inspect") no protocolo12 já deliberado, sem novos RPCs. O mesmo orçamento de sequência/taxa da InteractionAuthority deve controlar inspeção e objetos: contadores separados criariam saltos superiores a64 quando o cliente alternasse muitas ações de tipos diferentes.

InvestigationAuthority por sala depende de RoundAuthority, AuthoritativeWorld, BodyRegistry e LobbyRegistry. inspect é chamado pela InteractionAuthority após gate e consumo do orçamento; revalida participante vivo e rodada, alvo existente, alcance2.5m e LOS estático/dinâmico. Nenhuma permissão inédita de detetive: todos os participantes vivos podem consultar fatos públicos, desconhecido/morto/espectador não pode.

Resultado privado exato: request_id(int), round_id(int), body_id(int), label(String público), condition(String fixo "eliminado"). Sem papel, instigador, inventário, arma, probabilidade, timestamp inventado ou enumeração de corpos inexistentes. Só o último resultado por destinatário, limitado ao número de participantes, sai em seu próprio world_snapshot como inspection. Cliente valida allowlist/rodada e deduplica apresentação por request_id. Duas pessoas podem consultar o mesmo corpo sem exclusividade de posse; nenhuma consome evidência do outro.

Controles: I para corpo próximo; E/F/G/Q continuam objetos/coleta. Feedback deve diferenciar recusa de autorização/alcance/linha e sucesso por texto claro. Reset remove resultados. Desconexão remove estado individual; cadáver oficial permanece conforme regra anterior. Ao faltar nome de jogador desconectado, rótulo neutro sem inferir papel.

Testes necessários: corpo criado apenas após eliminação oficial; inspeção por dois participantes; ausente/morto/desconhecido/foraalcance/atravésdeporta; resultado privado por destinatário; DTO com segredo recusado; cópia independente/reset; alternar65+interações/inspeções sem contadores incompatíveis. Habilidades assassino/detetive/ressurreição continuam pendentes em specs futuras.
