# Suspeitos — entrega Fase 2, SPECs 09–16

Branch `codex/gameplay-specs-09-16`, base validada `59926cb74c6861c207ad16f7ad2793ea55bc9995` (PR31). PR consolidado: consultar o PR cuja head é essa branch. Ele usa `codex/gameplay-specs-01-08` como base enquanto o PR31 permanece aberto; o diff desta fase não presume os SPECs anteriores na main. Este relatório acompanha o código; o resultado remoto de CI no SHA final e o link direto são registrados no PR para não criar outro commit apenas para atualizar status.

## Status real

| SPEC | Entrega | Evidência principal |
| --- | --- | --- |
| 09 | Implementado: 20 portas e 3 objetos, posse exclusiva, pegar/soltar/empurrar, colisão oficial compartilhada entre movimento, previsão e tiros | [Física](09-physics.md), 45 checks; laboratório nativo separado |
| 10 | Implementado: passos e sons aceitos de portas/objetos/recarga, pool 3D limitado, volumes por categoria incluindo zero | [Áudio](10-audio.md), 33 checks finais; correção da revisão |
| 11 | Implementado: estados procedurais de disparo/recarga/interação/dano/morte, interrupções e reduzir movimento | [Animação](11-animation.md), 35 checks novos |
| 12 | Implementado: inspeção privada de corpo oficial, alcance/LOS/vida/rodada, sem revelar segredos | [Investigação](12-investigation.md), 93 checks |
| 13 | Implementado: interação e pistas contextuais integradas à mansão existente | [Mansão](13-mansion.md), 74 checks |
| 14 | Concluído documentalmente conforme alternativa da SPEC; nenhuma IA/NPC/plugin em produção | [Avaliação IA/diálogo](14-ai-dialogue.md) |
| 15 | Implementado/medido: codecs compactos e correção de lifecycle do helper de atraso | [Desempenho](15-performance.md), 23 checks codec +42 lifecycle |
| 16 | Integração automatizada, regressão, revisão e workflow de validação; certificação limitada às plataformas/cenários executados | [Certificação](16-certification.md), evidências abaixo e CI do PR |

## Alterações e contratos

A lista exata de arquivos é reproduzível com `git diff --name-status 59926cb..HEAD`; o separador Files changed do PR mostra somente esta fase. Grupos de implementação:

- `shared/environment_rules.gd`, `server/interaction_authority.gd`, `client/environment_view.gd`: catálogo, autoridade e apresentação; integração em World, MovementRules, CombatAuthority, PlayerPrediction, MatchRoom e ArenaView.
- `shared/sound_event_rules.gd`, `server/sound_event_authority.gd`, `client/spatial_audio_controller.gd`: eventos públicos aceitos e vozes; configurações/menu/CombatFx mantêm apresentação local.
- `client/character_action_state.gd`, CharacterAnimator e ArenaView: animação visual sem escrever mira, colisão ou dano oficial.
- `shared/investigation_rules.gd`, `server/investigation_authority.gd`, NetworkApp e RoundHud: resposta somente ao leitor autorizado, reutilizando BodyRegistry e o orçamento de interações.
- NetSync/NetworkConfig/NetworkApp: protocolo12, mesmos métodos RPC de produção, payloads compactos e rejeição explícita de clientes antigos. Expectativas Web/container atualizadas para12, sem remover assertivas.
- `tests/`: sete suítes novas, laboratório, benchmarks e harness real 4/8 clientes; helper NetDelayPeer tem ciclo de referência corrigido. `.github/workflows/gameplay-phase2.yml` acrescenta validação sem publicação.
- `docs/phase2/`: plano, decisões, pesquisa e evidências. Nenhum asset, addon ou engine externo foi importado.

DTOs, limites e lifecycle completos: [contratos](architecture-contracts.md). Mudança de protocolo requer atualizar cliente e servidor juntos num deploy futuro autorizado; a compatibilidade com11 é recusa legível, não interoperabilidade.

## Testes e identidade das evidências

- Baseline limpa59926cb: **37/37** suítes e **5/5** harnesses iniciais. [Baseline](baseline.md) distingue diagnósticos antigos de erros novos.
- Após a única correção Important final: **44/44 suítes PASS**, com status, marcador e zero SCRIPT/Parse/engine ERROR exigidos. Cada teste, duração, exit e marcador está em [final-unit-results.json](evidence/final-unit-results.json). Áudio passou33 checks. Três avisos ObjectDB de fixtures preexistentes continuam documentados.
- Regressão independente: **44/44 suítes no arquivo limpo, importação completa e29/29 cenários de transporte/auxiliares PASS**, incluindo4local/4RTT200/8clientes×3rodadas da Fase2. Evidências de importação e transporte: [final-regression.md](evidence/final-regression.md) e [JSON individual](evidence/final-regression-summary.json). O artefato congelado é **a8e6db6**, anterior à correção apenas de roteamento de volume; não se atribuem esses logs ao commit posterior.
- Revisão independente do diff inteiro: [parecer original](evidence/final-review.md), um Important e nenhum outro achado confirmado. [Resolução](evidence/review-resolution.md): RED32/2falhas → GREEN33/0 e44/44 após correção. Parecer não foi reescrito como aprovação posterior pelo próprio autor.
- Evidências de desenvolvimento e métricas mantêm SHAs/fingerprints próprios. Testes positivos novos têm gate de erro estrito e encerramento de todos os processos. Fixtures multiplayer usam setup explícito de posições/armas no servidor e comandos RPC de produção; não substituem playtest humano.
- CI remoto: verificar todos os runs do SHA final no PR, incluindo duplicatas push/PR. Exports Web/Windows, smoke Windows e container só recebem PASS depois de execução hospedada; não foram inferidos de unitários locais. `deploy-pages` e `web-probe` são skips esperados neste evento; skip não é aprovação de publicação.

## Comparativos e orçamento

Mesma carga de modelo de oito jogadores ativos: baseline280.90µs/tick e1772B/snapshot/destinatário; Fase2 antes da otimização790.41µs e9978.07B; depois **623.58µs e3332B**, redução de **66.6%** do payload da Fase2. O custo permanece acima da baseline porque há sistemas adicionais. A533120B/s agregados estimados a20Hz para8clientes, o orçamento deve ser acompanhado em rede real.

Bytes são serialização Variant, sem framing/TCP; tempo é parede do modelo, não CPU% nem throughput medido. Decode23objetos+32eventos ~0.30ms/snapshot neste host. Cena carregada em llvmpipe960×540: p95 baseline29.138/31.247ms, Fase2 40.428/32.675ms (primeiro/repetição); perfil baixo24.266→20.083ms. Há variabilidade/outlier explícito, sem atribuição causal indevida. Nós707→746; memória estática46.64→47.99MB. Seis runs verdes sem mutação de mira/estado oficial. [Relatório completo e dados](15-performance.md).

## Referências e licenças

[Inventário](references.md) registra os oito commits integrais, versões, licenças, dependências e links dos arquivos consultados: Godot Jolt, O3DE, State Charts, XR Tools, Dialogue Manager, Terrain3D, The Dark Mod e OpenMW. Nenhum código/asset foi reutilizado; GPL e assets restritos ficaram apenas como estudo conceitual. Dialogue Manager atual exige4.6 e Terrain3D atual4.5; candidatas compatíveis são documentadas, não instaladas. Procedência dos assets antigos continua pendência da auditoria anterior.

## Experimental, adiado e futuro

**Experimental:** laboratório isolado GodotPhysics/Jolt, oclusão sonora AABB implementada/testada mas desligada, benchmarks sintéticos/software. O laboratório não seleciona backend de produção nem certifica solver rígido geral.

**Não entregue/adiado:** solver rígido arbitrário/empilhamento/ragdoll, sprint e regras verticais não definidas, poderes de papel indefinidos, NPCs/árvores de comportamento/diálogos em runtime, Terrain3D/mapa externo, voz e trilha ambiente contínua. O fechamento visual da porta usa deslocamento para o batente; não é dobradiça física. Carregamento usa sweep e liberação segura limitada, não garante toda combinação física possível.

**Validação futura necessária:** playtest humano de áudio/conforto, GPU física, Android/macOS, rede remota com perda/reordenação, percentuais CPU/RSS e tráfego real por sessão. Diagnósticos legados de desconexão/RPC negativo e três avisos ObjectDB são separados das execuções novas estritas no relatório de regressão. O laboratório Jolt emitiu uma advertência de limite de jobs embora tenha atingido repouso; essa execução não é benchmark limpo e Jolt não foi ativado em produção. Nenhuma falha conhecida foi ocultada como PASS global de logs.

**Próxima fase:** executar o [roteiro humano](playtest.md), decidir tuning a partir desses registros, resolver procedência antiga, testar orçamento na infraestrutura real e definir regras de qualquer nova habilidade antes de implementá-la.

## Decisões e custos

1. Física analítica limitada para bloqueadores competitivos; native Physics/Jolt apenas laboratório. Preserva geometria/replay; custa ausência de dinâmica rígida arbitrária.
2. Protocolo12 explícito e mesmos RPCs. Evita clientes antigos ignorarem colisões; exige atualização coordenada cliente/servidor.
3. Sem sprint, poderes indefinidos ou NPCs inventados. Preserva regras; funcionalidades futuras precisam de especificação.
4. Oclusão AABB opcional desligada. Evita custo/legibilidade não certificados; padrão não abafa por parede.
5. Todos os participantes vivos inspecionam somente fatos públicos. Evita inventar exclusividade do detetive; política especial futura exige regra explícita.
6. Catálogo e ring contíguo no codec. Reduz bytes mantendo DTOs; ordem/enum exigem versionamento e há custo de decode.
7. Recarga remota segue combate. Corrige o contrato de mute; categorias agora são consistentes entre atores, sem efeito no servidor.

A revisão não certificou plataformas/CI/escuta/licenças antigas ou commits posteriores por inferência; as evidências externas estão atribuídas acima. Nenhum achado Minor confirmado ficou adiado.

## Operação, proteção e merge

[Como executar e testar](playtest.md). Godot4.4.1 obrigatório; cloud tem também4.6.3 no PATH e não deve usá-lo para esta certificação. Builds de CI são artifacts para revisão, não publicação. Não houve merge, auto-merge, deployPages/Railway, alteração de main, credenciais ou proteção.

Proposta não aplicada: PR obrigatório, pelo menos uma revisão independente humana, conversas resolvidas, aprovações invalidadas por novo commit, branch atualizada e bloqueio de force-push/exclusão/bypass rotineiro. Checks obrigatórios GitHubActions no SHA atual: `network-tests`, `netcode-tests`, `match-tests`, `menu-tests`, `rooms-tests`, `server-container`, `build-web-demo`, `export-windows`, `smoke-windows`, `gameplay-specs`, `gameplay-phase2`. `probe` é condicional e não deve ser exigido em todo PR; o aviso de protocolo antigo em produção não certifica um deploy novo.

O token já comprovou push/PR; a auditoria anterior recebeu403 para administração de proteção e não provou escrita. Nenhum PUT de teste foi enviado. Administrador deve aplicar a política pela interface ou credencial Administration:write após autorização e leitura completa da configuração atual, conforme [proposta anterior](../gameplay-research/spec-automation.md). Não habilitar auto-merge/mergequeue sem tarefa autorizada e suporte merge_group.

Riscos de merge: dependência dos PRs anteriores abertos; protocolo incompatível com builds11; custo adicional de payload/cena; validações humanas/plataformas e licenças antigas pendentes. Merge na main atualmente pode disparar Pages e a integração Railway externa; aprovação técnica não autoriza publicação. Revisar/autorizar essa operação separadamente, com plano de atualização coordenada e rollback. A execução autônoma dentro da branch está autorizada; merge/publicação continuam fora da missão.
