# SPEC12 — investigação genérica de corpos oficiais

Reutilizados BodyRegistry/BodyRules; nenhuma cópia paralela de cadáveres. InteractionAuthority compartilha o mesmo orçamento de sequência/taxa entre portas, objetos e inspect. Intenção `[interact,id,body:<id>,inspect]` atravessa os mesmos comandos/época/gates existentes, sem novo RPC.

InvestigationAuthority por sala valida participante vivo, objeto oficial da rodada, alcance2.5m e linha de interação estática/dinâmica. Dois participantes podem inspecionar o mesmo corpo. Desconhecido/morto/distante/alvoausente/portaentreosdois são recusados. O servidor guarda apenas o último resultado autorizado por solicitante; snapshot individual inclui somente a inspeção desse peer, nunca dos demais.

Allowlist exata do resultado: request_id, round_id, body_id, label público e condition="eliminado". Nenhum papel, autor, arma, inventário, chance, custo, cooldown ou horário inventado. Reset remove resultados; desconexão limpa estado individual mantendo o cadáver conforme a regra existente. Cliente valida DTO/rodada e mostra texto privado; I procura corpo próximo. Não se exige papel de detetive para um fato que já é público; habilidades especiais continuam pendentes.

## Testes

- RED inicial: contrato inexistente.
- Unitário novo: **93checks PASS**: dois leitores, resposta individual, morto/desconhecido/distante, alvoausente, portafechada/aberta e LOS, malformados/segredoextra, cópias/isolamento/reset;65+inspeções seguidas de porta provam orçamento contínuo; view reutiliza corpo e apresenta/limpa texto.
- Runner completo **41/41suítes PASS**, exit/marcadores e gateSCRIPT/Parse/engineERROR; três avisosObjectDB antigos discriminados anteriormente.
- Novo harness real **servidor+4clientes RTT200 PASS**, incluindo corpo gerado por tiros aceitos, duas inspeções, respostas apenas aos solicitantes, recusa morto/distante e shutdownlimpo. O resultado8×3 será fechado noSPEC16, sem herdar aprovação deste teste.

Evidência `/workspace/.ossuspeitos-state/phase2/spec12/` e `/workspace/.ossuspeitos-state/phase2/network-dev/investigation/`. A criação direta de registros no unitário é preparação confiável do servidor; somente o harness real comprova a cadeia tiro→morte→corpo→inspeção pela rede.

## Pendentes

Arma especial de um tiro, punição do detetive e ressurreição não recebem valores ou regras novas. Inspeção não identifica assassino nem reconstrói autoria balística. Reconexão online continua sujeita à regra preexistente de entrada apenas no lobby/contagem; não promete reentrada durante rodada ativa.
