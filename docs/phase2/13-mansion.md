# SPEC13 — mansão interativa

A integração conserva a mansão oficial, suas paredes/vergas/móveis,24luzes e perfis gráficos. Vinte vãos existentes recebem portas compartilhadas inicialmente abertas; escritório/salão/cozinha recebem três objetos físicos autoritativos. Não há mapa externo, terrain, destruição ou reconstrução da geometria.

Mesmos tamanhos/centros do catálogo alimentam meshes, colisão e tiro. Porta aberta fica fora do vão, fechada coincide com o AABB oficial; fechar sobre jogador/objeto é recusado. Portas mudam linhas de passagem/tiro; objetos podem ser disputados, carregados/soltos ou empurrados, gerando pistas sonoras apenas em eventos autorizados. Estes são os comportamentos emergentes pequenos pretendidos, sem solver independente do cliente.

Nesta etapa foram corrigidos indicadores/seleção: E só escolhe portas, mesmo quando há prop mais próxima; F não promete carregar objeto pesado. Limite público de4kg tem uma única constante compartilhada, usada na apresentação e na autoridade. Prompt distingue leve/pesado/posse e pode exibir inspeçãoI junto de interação. Recusas apresentam português claro para massa, obstáculo, alcance, posse, objeto/corpo ausente, intervalo e ação indisponível; não mostram nomes de RPC/protocolo.

## Verificação

- RED: E selecionava prop, F anunciava pesado e não havia hint contextual.
- `environment_presentation_test.gd`: **74checks PASS**,23meshes, dimensões exatas, folhas abertas fora do vão/fechadas no centro, massa/posse/ações, mensagens e apresentação sem mutação do snapshot.
- Suíte completa **42/42 PASS** (gate de exit/marcador/erros). Logs `/workspace/.ossuspeitos-state/phase2/spec13/`.
- Harness de desenvolvimento com transporte real:4local,4RTT200 e8×3local PASS,28/28/84assertivas, privacidade/reset e shutdown; ver evidence/network-development.md. Essa execução antecede o ajuste de hints13; não houve mudança de regras nessa correção. A validação final/CI executa sobre a revisão final.
- Smoke gráfico da fase11 já confirmou mansão/avatares/corpo; cena carregada de fase2/benchmark será registrada na fase15.

## Limites

Iluminação existente foi preservada; nenhum recurso novo oculta jogadores ou muda a autoridade. Não foi acrescentada trilha ambiente contínua: sons ambientais relevantes são portas/objetos/passos, separados dos efeitos competitivos. Uma trilha futura precisa de desenho de legibilidade/volume/asset próprio e não é condição para as interações atuais. Terrain3D foi apenas pesquisado; nenhum addon/asset importado. As medições4/8 e compatibilidade de exports são fechadas nos SPEC15/16.
