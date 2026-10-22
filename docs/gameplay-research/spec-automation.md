# Automação por SPECs — proposta de operação

Status: **preparação para revisão; nenhuma política aplicada**.
Data: 2026-10-21. Repositório: CarloshenAssis/ossuspeitos.
Base auditada: `dd15ff2ab29d5e67fccedc41c431c30eb7e32c6d`.
Escopo aprovado nesta tarefa: documentação, auditoria SPEC 00, branch, push e PR.
Sem merge, publicação, alteração de proteção ou auto-merge.

## Estado observado e limites da verificação

- GitHub REST e GraphQL acessíveis; identidade autenticada `CarloshenAssis`.
  `GH_TOKEN` está presente; nenhum valor foi registrado.
- Repositório informa `permissions.push=true` e `permissions.admin=true`;
  GraphQL informa `viewerPermission=ADMIN`. Isso não substitui as permissões
  específicas da integração/token.
- `GET /repos/CarloshenAssis/ossuspeitos/branches/main/protection` retorna
  **403 Resource not accessible by integration**. O cabeçalho declara
  `X-Accepted-GitHub-Permissions: administration=read`.
- GraphQL `defaultBranchRef.branchProtectionRule=null`; branch REST
  `protected=false`; regras efetivas e rulesets retornam listas vazias.
  São evidências de main desprotegida, com limite de acesso ao endpoint detalhado.
- `allow_auto_merge=false` foi preservado.
- Escrever proteção por API exigiria a permissão de repositório
  **Administration: write** e privilégio administrativo. A permissão de escrita
  de proteção **não foi comprovada**: não há teste seguro de PUT que garanta
  ausência de alteração. Não enviar PUT/PATCH experimental. O 403 na leitura
  impede declarar essa capacidade disponível.
- Confirmação prática de branch/push/PR: consultar o PR desta branch e seu
  `head.sha`; o relatório de entrega registra o resultado. Nenhuma ref da main
  é alvo do push.

Não é necessário trocar ou revelar o token para trabalhar nos documentos.
Se houver autorização futura para administrar políticas, ajustar a integração
GitHub nas configurações seguras, com acesso apenas a este repositório; não
colocar credenciais em arquivos, comentários, logs ou SPECs.

## Proteção proposta para main

Configurar depois da revisão, pela interface do GitHub em **Settings → Rules →
Rulesets** (ou **Branches → Branch protection rules**, sem duplicar regras):

1. Regra ativa visando somente `main`.
2. Exigir Pull Request; mínimo **uma aprovação humana**, invalidar aprovação
   após novos commits e exigir resolução de conversas. O autor não aprova o
   próprio PR; se não houver outro revisor disponível, decidir explicitamente
   um fluxo de revisão externa antes de ativar esse requisito.
3. Exigir os nove checks da [matriz](test-matrix.md), com origem GitHub Actions:
   `network-tests`, `netcode-tests`, `match-tests`, `menu-tests`,
   `rooms-tests`, `server-container`, `build-web-demo`, `export-windows`,
   `smoke-windows`. Confirmar nomes na execução do PR. Exigir branch atualizada
   com main antes do merge; novos commits exigem nova validação do SHA.
4. Bloquear force-push e exclusão da main. Aplicar também a administradores,
   sem bypass rotineiro da automação. Restringir alterações das regras a humanos
   responsáveis. Não usar push direto como alternativa a PR bloqueado.
5. Manter auto-merge desativado nesta fase. Não habilitar merge queue antes de
   adaptar/testar o evento `merge_group`, hoje ausente nos workflows.
6. Opcional em tarefa própria: CODEOWNERS para contratos/rede/workflows e revisão
   por área. Não presumir que esse arquivo existe.

Payload ilustrativo da API legada, **não executado**. `contexts` pode ser trocado
por `checks` com `app_id` verificado da instalação GitHub Actions para vincular
a origem. Não adivinhar IDs:

```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "network-tests", "netcode-tests", "match-tests", "menu-tests",
      "rooms-tests", "server-container", "build-web-demo",
      "export-windows", "smoke-windows"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
```

Antes de qualquer aplicação futura: obter política atual completa com credencial
autorizada, preservar requisitos já existentes, apresentar diff da política e
aplicar somente após autorização explícita. Um PUT substitui configurações;
não usar este exemplo para sobrescrever uma regra desconhecida. Se o token
continuar sem permissão, o administrador aplica a mesma proposta na interface.
Depois, consultar regras efetivas e testar num PR autorizado; não testar
violação com push na main.

## Fluxo por SPEC

1. Ler master, auditoria, contratos, matriz e decisão de aprovação anterior.
2. Atualizar refs por fetch; inspecionar alterações locais e preservar trabalho.
   Criar branch `spec/NN-descricao` a partir do SHA aprovado de main; usar o
   checkout isolado do cloud, sem worktree adicional salvo pedido.
3. Registrar escopo e casos de aceitação antes de implementação. Consultar os
   arquivos externos apenas no SHA/licença registrados; não copiar GPL ou assets
   sem licença individual.
4. Executar teste novo que falha pelo motivo esperado; implementar incremento
   mínimo, validar testes novos e regressões, métricas antes/depois e limites.
5. Commit com escopo da SPEC, push apenas da branch, PR para main com resumo,
   licença, lista de contratos, comandos, resultados e pendências. Confirmar
   `head.sha` remoto corresponde ao commit testado.
6. Aguardar os nove checks no SHA atual e revisão humana. Falha, check ausente,
   cancelado ou não executado não é sucesso; não remover testes para liberar.
7. **Não fazer merge automaticamente.** Após autorização explícita, o responsável
   integra o PR aprovado e só então inicia a etapa seguinte. SPEC 01 fica bloqueado
   até aprovação do SPEC 00.
8. Registrar eventual mudança de protocolo em PR com migração de todos os
   consumidores (incluindo clientes Web/Windows/servidor), rejeição clara de versão
   incompatível e evidências. Não mudar transporte por conveniência.

Execução automática dentro da fase inclui implementar/testar/corrigir e abrir
PR; não inclui ultrapassar aprovação da SPEC, mudar proteção, merge ou deploy.

## Merge e publicações: estado e proposta futura

| Evento atual | Consequência |
| --- | --- |
| Push da branch desta preparação | Godot network tests; nenhum job de publicação Pages por esse evento |
| PR para main | Network, container, Web e Windows; artifacts de teste; `deploy-pages` não executa |
| PR alterando arquivos filtrados de endpoint/protocolo | Também Online server probe, que toca produção; não alterar esses arquivos nesta preparação |
| Push em main após merge | Network, container e Web; Web publica Pages quando seu build passa |
| Execução manual Web | Também pode publicar Pages |
| Online server probe | Manual ou PR filtrado; não executa por push em main |
| Railway | Docs indicam integração com main; configuração externa, previews e Wait for CI não foram verificados pelo GitHub |

A publicação Pages depende só do job `build-web-demo` no workflow atual,
**não de todos os outros checks pós-merge**. `github-pages` está limitado à
branch main e não declara required reviewers nesta consulta. Nenhum workflow
foi alterado nesta preparação.

Proposta para uma tarefa posterior autorizada: manter builds/testes em PR,
separar deploy num workflow de release manual ou condicionar deploy à aprovação
do ambiente e à validação de todos os checks no mesmo SHA; definir rollback e
registrar versão aprovada. Só autorizar publicação automática quando o usuário
aceitar expressamente que merge publica. No Railway, revisar Git branch,
PR environments, permissões e Wait for CI no painel antes de prometer
ausência de deploy ou um fluxo totalmente automático. Não é possível certificar
essa configuração externa apenas por `railway.json`.

Nesta tarefa: sem merge, sem despacho manual de workflow, sem chamada Railway,
sem alteração de main/proteção/auto-merge. Publicações futuras exigem autorização
e não são consequência implícita de aprovação técnica do SPEC 00.
