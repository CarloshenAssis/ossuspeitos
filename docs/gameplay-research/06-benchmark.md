# SPEC 06 — perfis visuais e medição Compatibility

Preferência local `graphics_profile` em `user://settings.cfg`: `low`, `baseline`
(padrão) e `high`; ausente ou inválida volta a `baseline`. Em Configurações,
**Qualidade gráfica** alterna **Baixa → Padrão → Alta (texturas)**. A mudança
é salva e aplicada na próxima abertura da arena e ao consumidor de settings
ativo. Não contém segredos nem muda protocolo.

- **Padrão:** materiais originais, 24 luzes pontuais sem sombras, sem mudança
  no ambiente ou na direcional. Restaurar o perfil remove os overrides.
- **Baixa:** mesmos materiais/texturas e geometria, iluminação por vértice e
  componente especular desativada. Pode apresentar iluminação menos uniforme
  em superfícies grandes; não remove jogadores, obstáculos ou pickups.
- **Alta:** filtragem anisotrópica somente dos materiais com textura albedo;
  os materiais sem textura conservam o filtro original. Luzes e sombras ficam
  no estado original. O experimento anterior mostrou superfícies negras no
  llvmpipe com sombras e também com sombras desativadas; a causa precisa não
  foi demonstrada. Não usa recursos exclusivos de Forward+.


Os materiais de cada perfil opcional são cópias compartilhadas somente dentro
daquela aplicação à vista; nunca se modifica o cache global `MansionArt`.
Geometria, transformações e visibilidade ficam intactas. Não foram acrescentados
objetos físicos, `RigidBody3D`, colisões, efeitos ou autoridades independentes.
A física analítica oficial, blockers e hitscan permanecem os existentes.

## Reprodução e resultados

```sh
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
DISPLAY=:99 "$GODOT_BIN" --display-driver x11 --rendering-method gl_compatibility \
  --audio-driver Dummy --path . tests/scenes/graphics_benchmark.tscn -- --profile=low
```

Cena determinística: mansão real sem personagens, câmera fixa no Escritório
(3, 0,7, 4), yaw zero, 960×540; 248 meshes, 24 luzes. Janela Xorg dummy,
Compatibility/OpenGL 4.5, Mesa 25.0.7-2+deb13u1, llvmpipe LLVM 19.1.7
256 bits, CPU AMD EPYC 9V74, Godot 4.4.1 `49a5bc7b6`.
120 quadros de aquecimento, 300 amostras por execução. Percentis são nearest
rank (p50/150ª, p95/285ª, p99/297ª). Tempo de parede entre quadros apresentados,
inclui escalonamento/driver; tempo GPU isolado não foi medido. O driver informa
que não suporta mudar VSync. Headless/dummy é recusado (exit 2), nunca usado
como evidência de renderização.

| Perfil | p50 ms | p95 ms | p99 ms | max ms |
|---|---:|---:|---:|---:|
| Antes (6ff4bed) | 15.237 | 23.112 | 29.087 | 37.088 |
| Depois padrão | 15.853 | 24.429 | 31.612 | 128.290 |
| Depois baixa | 8.326 | 12.006 | 17.945 | 42.633 |
| Depois alta | 15.381 | 23.220 | 26.516 | 44.303 |

Antes: árvore limpa arquivada de `6ff4bed`, com exatamente a mesma cena de
benchmark. Depois: árvore SPEC06. Comparação final executada sequencialmente,
sem testes pesados em paralelo; logs `before-baseline-quiet.log` e
`quiet-{baseline,low,high}.log` em evidência externa `mission-sdd/spec06`.
Execuções exploratórias que coincidiram com a suíte não são a comparação final.
Screenshots procedurais locais `baseline.png`, `low.png`, `high.png` acompanham
os logs. A janela contém somente a vista 3D, sem interface de combate.

Isto mede **renderização por software**, não certificação de GPU desktop,
Android ou Web. Cena/câmera única não representa toda a mansão nem uma partida
cheia. Baixa reduziu o p95 observado de 24,429 para 12,006 ms nesta câmera.
Diferenças entre padrão/alta não demonstram ganho sistemático; a execução
padrão teve um outlier de 128,290 ms. O padrão é preservado; qualquer orçamento de plataforma/aceitação
visual em hardware real continua pendente. Alta é opcional e deve ser medida
no equipamento de destino.

## Verificação e referência

`graphics_profiles_test.gd` verifica default/entrada inválida/persistência,
restauração idempotente, materiais Compatibility, cache e duas vistas isoladas,
mesma geometria e impressão digital dos blockers, estados oficiais iguais,
jogadores visíveis, ausência de sombras novas/teto de 32 luzes e ausência de física nova.
Suíte dos 35 scripts `tests/*_test.gd`, testes focados de mapa/arte/movimento/menu/
câmera, servidor real + quatro clientes smoke e sync local foram executados.

Referência conceitual: Wicked Engine MIT, commit
`79243b535c226b1612449335d632f225e2303258`, seleção de custo de luz/sombra e
qualidade de materiais conforme capacidade do renderer. Implementação nativa
Godot; nenhum código, engine, plugin ou asset foi copiado/importado. Ver
[registro de licenças](license-register.md).
