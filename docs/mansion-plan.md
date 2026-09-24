# Mansão — plano e checkpoint

Referência de topologia: a planta aprovada, `planta_aprovada.png` (anexada à
tarefa; não versionada). As perspectivas anexadas servem só de atmosfera.

## Checkpoint

| Fase | Branch | Estado | PR | SHA |
| --- | --- | --- | --- | --- |
| Base | `main` | PRs #14 e #15 integrados | — | `996c536` |
| 1 — blockout jogável | `claude/charming-darwin-kz3xvn` | integrada | [#16](https://github.com/CarloshenAssis/ossuspeitos/pull/16) | `37b97fb` → merge `3b20af3` |
| 2 — identidade visual | `claude/charming-darwin-kz3xvn`, reiniciada de `3b20af3` | integrada | [#17](https://github.com/CarloshenAssis/ossuspeitos/pull/17) | `a23825b` → merge `60e478f` |
| 3 — repouso e caminhada | `claude/charming-darwin-kz3xvn`, reiniciada de `60e478f` | integrada | [#18](https://github.com/CarloshenAssis/ossuspeitos/pull/18) | `17d2706` → merge `7c98bd9` |
| 4 — resposta local e apresentação | `claude/charming-darwin-kz3xvn`, reiniciada de `7c98bd9` | integrada (ver `docs/netcode.md`) | [#19](https://github.com/CarloshenAssis/ossuspeitos/pull/19) | `79ba755` → merge `f8cd36c` |
| 5 — campanha integrada e build | `claude/charming-darwin-kz3xvn`, reiniciada de `f8cd36c` | integrada (ver `docs/test-matrix.md`) | [#20](https://github.com/CarloshenAssis/ossuspeitos/pull/20) | `f10ef87` → merge `f76d4cb` |
| 6 — reset completo, pickups e corpos | `claude/charming-darwin-kz3xvn`, reiniciada de `f76d4cb` | integrada | [#21](https://github.com/CarloshenAssis/ossuspeitos/pull/21) | `351a291` → merge `f82ad7c` |
| 6.1 — protocolo 10 | `claude/charming-darwin-kz3xvn`, reiniciada de `f82ad7c` | em PR | — | — |

Pendências:
- protocolo 10: PR, CI do HEAD, merge e build Windows identificada como protocolo 10.

Retomada: `git fetch origin && git checkout claude/charming-darwin-kz3xvn`.
Testes: ver `.github/workflows/godot-network-tests.yml`.

## Métricas medidas no código

- Corpo oficial: cápsula de raio 0,45 m e hitbox de 0,9 × 2,0 × 0,9 m.
  - A posição é o centro do corpo, a 1,0 m do piso.
  - O olho e a origem do tiro ficam a 1,7 m.
  - O personagem GLB tem 1,80 m.
- Velocidade máxima: 5 m/s, com aceleração de 18 m/s². A física roda a 60 Hz.
- Colisão oficial: circunferência contra AABBs, eixo por eixo, em sub-passos de
  no máximo 0,2 m.

## Dimensões escolhidas

- Grade de 0,5 m; paredes com 0,5 m de espessura (uma célula).
- Corredores com 3 m livres.
  - As passagens curtas entre cômodos vizinhos têm 2 m de comprimento e 3 m de
    largura.
- Portas com 2 m de vão livre por 2,4 m de altura. Sobram 0,55 m de folga por
  lado para o corpo.
- Tetos:
  - salas: 3,2 m;
  - corredores: 3,0 m;
  - Salão: 4,5 m.
- As paredes sobem até 4,7 m, acima de qualquer teto.

Dimensões internas: iguais às sugeridas, sem ajuste.

| Cômodo | Tamanho | Coordenadas (x, z) | Portas |
| --- | --- | --- | --- |
| Salão Central | 10 × 9 | 8,5–18,5 / 7,5–16,5 | N, O, L, S |
| Escritório | 6 × 5 | 0–6 / 0–5 | L, S |
| Biblioteca | 5 × 8 | 0,5–5,5 / 8–16 | N, L, S |
| Galeria de Retratos | 9 × 5 | 21–30 / −0,5–4,5 | O, S |
| Cozinha | 7 × 5 | 21,5–28,5 / 9–14 | O, N, S |
| Sala de Jantar | 9 × 5 | 9–18 / 19,5–24,5 | N, O, L |
| Quarto do Fundo | 5 × 6 | 30,5–35,5 / 22,5–28,5 | N |
| Quarto de Hóspedes | 5 × 5 | 38–43 / 22,5–27,5 | N |
| Banheiro | 3 × 3,5 | 42,5–45,5 / 10–13,5 | S |

- Eixos: +X é leste e +Z é sul.
- A casa ocupa cerca de 46 × 30 m.
- O maior percurso (Escritório → Quarto de Hóspedes) tem cerca de 56 m, ou
  11 s a 5 m/s.

## Conexões (planta aprovada)

- Escritório ↔ Biblioteca: corredor vertical curto.
- Escritório ↔ Galeria: corredor norte, com ramal para a entrada norte do
  Salão.
- Biblioteca ↔ Salão: entrada oeste do Salão.
- Biblioteca ↔ Sala de Jantar: corredor sudoeste, em L.
- Salão ↔ Cozinha (leste) e Salão ↔ Sala de Jantar (sul).
- Galeria ↔ Cozinha: corredor vertical.
- Sala de Jantar ↔ Cozinha (sul): a diagonal da planta virou um L modular, o
  corredor sudeste. Não há degraus, e as quinas são convexas; a colisão desliza
  por eixo.
- Do corredor ao sul da Cozinha sai a ala leste.
  - Trata-se de um corredor reto com três ramais, um para cada cômodo: Quarto
    do Fundo, Quarto de Hóspedes e Banheiro.
  - Nenhum desses cômodos é passagem para outro.
  - O vão branco sem nome da planta foi eliminado ao simplificar a ala em um
    único corredor reto. Não existe décimo cômodo.
- Banheiro: a porta encosta na parede leste do ramal, de modo que o Quarto de
  Hóspedes não enxerga o spawn do Banheiro através das duas portas alinhadas.

## Representação compartilhada

- `shared/mansion_map.gd` é a fonte única dos dados:
  - espaços (cômodos e corredores) com teto;
  - portas;
  - junções;
  - móveis;
  - spawns;
  - pickups.
- Paredes, vergas e tetos são derivados de forma determinística:
  - toda célula não livre vizinha de uma livre vira parede;
  - essas paredes são fundidas em caixas.
- `ArenaRules.BLOCKERS` expõe a lista, e servidor, cliente e testes a usam.
- O servidor headless carrega só esses dados. Não há cena, mesh, luz ou áudio.
- Movimento:
  - só consideram volumes com base abaixo de 2,0 m, ou seja, vergas e tetos
    não contam;
  - há um índice espacial em baldes de 4 m;
  - o algoritmo continua o mesmo: por eixo e com sub-passos.
- Tiro: o primeiro contato vale, entre piso, volumes (paredes, vergas, tetos,
  móveis) e jogadores.
- Mesas são tampo mais pés. O vão embaixo deixa o tiro passar; o corpo é
  barrado pela projeção do tampo.
- Os demais móveis são maciços.
- O cliente monta uma caixa por volume oficial, com o mesmo centro e tamanho,
  e um piso fino abaixo de y = 0.
- Inspeção (`debug_overlay` e `set_show_ceilings(false)`):
  - mostra nomes dos cômodos e marcadores de spawn;
  - recorta o teto só na apresentação;
  - fica desligada na apresentação normal.
