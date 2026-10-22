# Correção de importação no CI pós-integração

Os PRs30,31,32 foram integrados em sequência após seus novos heads terem todos os checks verdes. Cada árvore candidata foi comparada ao conteúdo validado antes do merge e conferida depois. Os merges foram d24a516,4796ef8,d49a27a. Os smoke tests após30/31 e a regressão independente pós32 (44GDScript,16casos Python,4RTT200 e8×3) passaram.

O CI pós-merge d49a27a detectou falha real em `avatar_facing_test.gd`: run39720577061, job119632841269, artifact12401330429. Não foi ignorada nem atribuída a flakiness sem investigação. O download direto do artifact redirecionou para um host indisponível neste ambiente; um job temporário na branch codex/integration-ci-diagnostics leu o mesmo artifact no Actions e expôs seus trechos como annotations (check119634131410). Essa branch de diagnóstico não é candidata a merge; seus runs restantes foram cancelados depois de salvar a evidência para evitar execução desnecessária.

## Causa observada

O workflow antigo usava `godot --headless --path . --editor --quit`. Em cinco arquivos limpos do mesmo commit, esse comando terminou0 mas interrompeu o scan/importação (`Scan thread aborted`). O teste seguinte tentou carregar `.godot/imported/mystery_character_ember.glb-794801586c4935f879a25333677e5f45.scn`, que não existia. O carregamento nulo causou19falhas em27checks. O artifact hospedado contém a mesma primeira falha de arquivo ausente e a mesma cadeia ArenaModels/ArenaView.

Importar completamente o MESMO arquivo de fontes corrigiu a preparação: três repetições do teste passaram27/27, sem erros, sem alterar uma linha de gameplay ou de assertiva. Os284arquivos rastreados continuaram idênticos ao d49a27a. O contraste `--headless --import` também concluiu o scan e recuperou o teste, mas emitiu oito erros de textura do renderer dummy; por isso a preparação estrita usa software gráfico, como o workflow Fase2 já validado.

Evidência individual: [avatar-import-reproduction.json](integration-evidence/avatar-import-reproduction.json). A primeira reparação gráfica não salvou o exit da importação separadamente; o relatório não o inventa. Os exits/marcadores dos testes posteriores foram observados. O workflow corrigido verificará o exit da importação e seus erros diretamente.

## Correção delimitada

Somente o job network-tests que executa os testes de modelos troca a importação abreviada por `--import` completo em Xvfb/Mesa Compatibility. O pipeline exige exit0 e ausência de SCRIPT/Parse/engineERROR, então restaura o project.godot exato do commit antes dos testes. Instala também mesa-vulkan-drivers para os importadores. A mesma dependência é explicitada no import do gate manual de Pages, mantendo os preparadores gráficos equivalentes.

Todos os passos de teste e suas assertivas permanecem. O prazo desse job sobe de15para20min para acomodar apt e importação completa; os watchdogs individuais não mudam. Nenhum outro prazo de teste é ampliado. Não se faz retry cego para obter verde. Nenhuma alteração em client/server/shared/assets, transporte, protocolo, backend de produção, licença ou credencial.

A correção foi revisada independentemente; nenhum achado Important no diff do job de rede. Builds/artifacts continuam permitidos, Pages continua retido por padrão e exige SHA aprovado+sonda estrita no servidor correspondente. Railway continua sob operação manual do usuário. Novos checks devem ser conferidos no head da correção e na main resultante antes de declarar encerramento.
