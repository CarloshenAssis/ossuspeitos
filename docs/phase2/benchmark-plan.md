# Plano de medição comparativa

Base congelada59926cb em /workspace/phase2-baseline; relato baseline.md. Reexecutar medições quando09–13estiverem integrados, com a mesma versão4.4.1, host, viewport960×540, Compatibility e llvmpipe. Não comparar hostocioso com testeconcorrente nem converter tempo observado em certificação GPU.

- Gráficos:120warmup/300amostras, p50/p95/p99/max; incluir snapshot real de23objetos, avatares e novasposes, enumerar contagemnodes/meshes/luzes. Repetir original/padrão/low se houver variância excessiva; sem repetição arbitrária para selecionar melhorresultado.
- Modelo servidor: MatchRoom4/8participantes, comandos reais no integrador, estático/interagindo; custo da simulação por lote, memória/objetos do processo e ringeventos. Separar modelo local do tempo com sockets.
- Transporte real: harness4/8registra tickrate60/snapshot20Hz, bytes estimados de Variant do payload novo comparados snapshot original, quantidade/ringáudio, objetos e overhead opcional. Nunca chamar estimativa Variant de bytes TCP totais.
- Lifecycle: baseline avisosObjectDB em três fixtures conhecidos; não atribuir automaticamente novos avisos ao baseline. Capturar processos e filas/vozes/eventos restantes.
- Plataformas: CIexecuta exportsWeb/Windows/smokeWindows/containerLinux; imagem/renderLocalsoftware só comprova comportamento do driver usado. Android/macOS/GPUreal não certificados.

Se novo estado periódico custar demais, avaliar encoding compacto derivando geometria estática do catálogo. Não reduzir confiabilidade de colisões para economizar bytes; não mudar intervalos/limites silenciosamente. Manter eventos públicos sem segredos e limitar trabalho fora de alcance. Pool de12vozes já elimina nópor evento; oclusão avançada permanece opt-in experimental.
