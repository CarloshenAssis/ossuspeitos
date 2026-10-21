# SPEC 00 — auditoria e preparação da automação

Status: **aguardando revisão humana**. Este diretório não autoriza executar SPEC 01,
fazer merge, modificar proteção da main, habilitar auto-merge ou publicar builds.

| Documento | Conteúdo |
| --- | --- |
| [master-spec-v1.md](master-spec-v1.md) | Master SPEC v1.0 fornecida pelo usuário, preservada |
| [00-baseline.md](00-baseline.md) | Estado real, versão, mapa de módulos, lacunas e riscos |
| [architecture-contracts.md](architecture-contracts.md) | Interfaces e invariantes que precisam ser preservados |
| [license-register.md](license-register.md) | Sete projetos consultados, commits e evidência de licenças |
| [test-matrix.md](test-matrix.md) | Checks comuns e casos adicionais por SPEC |
| [initial-test-report.md](initial-test-report.md) | Comandos executados, resultados, diagnósticos e limites |
| [implementation-plan.md](implementation-plan.md) | Plano incremental dos SPECs 01–08 adaptado ao código existente |
| [spec-automation.md](spec-automation.md) | Permissões, proteção proposta, branches, revisão, merge e deploy |

## Decisões que a revisão precisa resolver

1. Aprovar ou ajustar esta auditoria antes do SPEC 01.
2. Definir se e como evoluir movimento planar para salto/rampas sem quebrar replay,
   colisão e protocolo. Sprint/salto não estão implementados na baseline.
3. Preservar predição/reconciliação existentes; avaliar melhorias por métricas,
   sem reconstrução do networking.
4. Confirmar separadamente regras de armas especiais por papel antes de
   implementá-las; a pistola comum atual não implementa essas regras.
5. Aprovar futuramente uma política de main e publicação. A tarefa atual somente
   propõe essa política; merges continuam sujeitos a autorização humana.

Nenhum código externo, asset ou engine foi incorporado. Nenhum código de gameplay,
teste ou workflow precisa ser modificado para produzir os entregáveis desta fase.
