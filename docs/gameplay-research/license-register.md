# SPEC 00 — Registro de referências, licenças e compatibilidade

Consulta realizada em 21/10/2026 pela API do GitHub, com leitura dos metadados,
árvores e arquivos abaixo em commits imutáveis. As sete referências foram
consultadas; nenhuma delas foi compilada, executada ou incorporada ao Suspeitos.
Este documento registra pesquisa, não autoriza importação futura de código ou assets.

## Política de reutilização

- **Código externo incorporado neste PR: nenhum.** Modificações de código externo: nenhuma.
- Quake III e ioquake3: somente estudo conceitual e descrição independente.
  Não copiar, traduzir, adaptar ou portar funções GPL para GDScript.
- MIT/zlib: eventual reutilização exige registrar novamente URL, commit, caminho,
  autoria, licença, avisos preservados e modificações do trecho efetivamente usado.
- Licença do repositório não libera automaticamente dependências, modelos, mapas,
  sons, fontes ou texturas. Assets permanecem fora de escopo até verificação individual.
- Os commits abaixo fixam o material desta auditoria; tags são referências adicionais,
  não substitutos dos commits. Sem tag significa nenhuma tag retornada na consulta,
  não prova de ausência de versões históricas fora do GitHub.

## Inventário fixado

| SPEC | Repositório e branch consultada | Commit completo | Data do commit (UTC) | Versão/tag observada |
| --- | --- | --- | --- | --- |
| 01 | [Whimfoome/godot-FirstPersonStarter](https://github.com/Whimfoome/godot-FirstPersonStarter), `main` | `893db99a10eedadbd8189c040fb4d41fdf6ca46a` | 25/04/2024 | `project.godot`: Godot 4.2; tag `v1.3` aponta a `c9f77c321f63d37ad2d6067107c9c930aa1fae18`, diferente do commit auditado |
| 02 | [id-Software/Quake-III-Arena](https://github.com/id-Software/Quake-III-Arena), `master` | `dbe4ddb10315479fc00086f08e25d968b4b43c49` | 31/01/2012 | Fontes da publicação GPL de 20/08/2005; sem tags retornadas |
| 03 | [redeclipse/base](https://github.com/redeclipse/base), `master` | `21bd045fd76e0bf50a4e0205300d599bff182369` | 18/10/2026 | Desenvolvimento; tag `v2.0.0` em `4117baee090baa71b0116599c415998aff9839c3`, diferente do commit auditado |
| 04 | [jspjut/cube2](https://github.com/jspjut/cube2), `master` | `f3e1cd1b3ff6fd80946562f5a24b4e3451004473` | 30/01/2015 | Snapshot histórico de Sauerbraten; sem tags retornadas |
| 05 | [godotengine/tps-demo](https://github.com/godotengine/tps-demo), `master` | `a82f15448e9b015440d3bbdf5e10801b260c4e9f` | 31/08/2026 | Tag `4.7-a82f154` no mesmo commit; manifesto Godot 4.7; mensagem do commit cita atualização para 4.7.2 |
| 06 | [turanszkij/WickedEngine](https://github.com/turanszkij/WickedEngine), `master` | `79243b535c226b1612449335d632f225e2303258` | 21/10/2026 | Desenvolvimento; tag `v0.72.120` em `df44c3db4c4927492bc9c791eac715d98d7ed091`, diferente do commit auditado |
| 07 | [ioquake/ioq3](https://github.com/ioquake/ioq3), `main` | `87a99d18206e878a20289f05ac3c16005dcae5c3` | 12/10/2026 | Desenvolvimento; sem tags retornadas |

## Evidência por referência

### 01 — FirstPersonStarter

- [LICENSE](https://github.com/Whimfoome/godot-FirstPersonStarter/blob/893db99a10eedadbd8189c040fb4d41fdf6ca46a/LICENSE): MIT;
  copyright 2019–presente Dimitar “Whimfoome” Dimitrov. Preservar aviso e permissão em cópias substanciais.
- Arquivos estudados: `project.godot`, `Player/MovementController.gd`.
  A árvore também identifica `Player/Head.gd` e `Player/Sprint.gd` como candidatos
  para inspeção detalhada no SPEC 01; estes dois arquivos não foram auditados nesta etapa.
- O controlador usa `CharacterBody3D`, `_physics_process`, aceleração/desaceleração,
  controle aéreo, gravidade e `move_and_slide()`. A configuração declara Godot 4.2.
- Compatibilidade: APIs da família Godot 4, mas não foi realizado teste de importação
  em 4.4.1. O Suspeitos usa simulação compartilhada/autoridade própria; substituir
  seu controlador por física local criaria divergência. Estudar parâmetros e integrar
  na simulação existente, preservando replay e validação. Não importar cena pronta.

### 02 — Quake III Arena

- [COPYING.txt](https://github.com/id-Software/Quake-III-Arena/blob/dbe4ddb10315479fc00086f08e25d968b4b43c49/COPYING.txt): texto GPL v2.
  Cabeçalho de `code/cgame/cg_predict.c` declara copyright 1999–2005 Id Software e
  **GPL v2 ou posterior**; o rótulo GPL-2.0 da API não representa todos os avisos por arquivo.
- Arquivos consultados: `code/cgame/cg_predict.c`, `code/game/bg_pmove.c`,
  `code/qcommon/q_shared.h`, `code/client/cl_input.c`, `code/server/sv_snapshot.c`, `code/qcommon/msg.c`.
- Conceitos: comandos com sequência/tempo, simulação prevista, snapshots e confirmação
  do estado oficial. Descrever requisitos independentemente e compará-los com o
  que o Suspeitos já possui; não reproduzir estruturas nem funções GPL.
- Compatibilidade: engine C própria e transporte/protocolo diferentes. Não é addon
  Godot, não será ligada nem portada. Código e assets comerciais têm escopos distintos.

### 03 — Red Eclipse

- [doc/license.txt](https://github.com/redeclipse/base/blob/21bd045fd76e0bf50a4e0205300d599bff182369/doc/license.txt): zlib para fontes, scripts shell e configuração relacionados;
  copyright Red Eclipse 2009–2025 Quinton Reeves, Lee Salzman e Sławomir Błauciak,
  com atribuições adicionais a Tesseract/Cube Engine 2.
- Arquivo estudado: `src/game/weapons.cpp` (seleção, recarga e estado de arma).
  Conceito útil: separar definição, estado, comandos de troca/recarga e apresentação.
- zlib exige não deturpar origem, marcar alterações e preservar aviso nas fontes.
  ENet e bibliotecas em `bin/` têm licenças próprias; `doc/all-licenses.txt` é o índice
  indicado pelo próprio projeto, não uma autorização global de assets.
- Assets não são zlib; o texto prevê licenças individuais e CC-BY-SA 4.0+ quando não
  houver licença explícita. Nenhum asset foi selecionado ou liberado nesta auditoria.
- Compatibilidade: engine C++ derivada de Tesseract/Cube, sem integração nativa Godot.
  Adaptar conceitos ao `WeaponRules`/autoridades existentes; não importar engine.

### 04 — Cube 2 / Sauerbraten

- [src/readme_source.txt](https://github.com/jspjut/cube2/blob/f3e1cd1b3ff6fd80946562f5a24b4e3451004473/src/readme_source.txt): zlib; copyright 2001–2015
  Wouter van Oortmerssen, Lee Salzman, Mike Dysart, Robert Pointon e Quinton Reeves.
  Texto cobre fontes em `src/` e `.cfg` em `data/`; ENet tem licença MIT-style própria.
- Arquivos estudados: `README.html`, `src/readme_source.txt`, `src/fpsgame/weapon.cpp`.
  Conceitos: alcance, dispersão, geração de raios e separação de efeitos/projéteis.
- Avisos zlib devem ser preservados e modificações identificadas. Mídia tem licenças
  e restrições individuais; `README.html` alerta explicitamente que ausência de aviso
  não implica liberdade de uso. Nenhuma mídia foi selecionada.
- Compatibilidade: engine C++/OpenGL/SDL de 2015; não é componente GDScript. Sua aleatoriedade
  não deve ser transplantada: qualquer spread futuro do Suspeitos será escolhido,
  validado e reproduzido no servidor. Não adicionar balística custosa por referência.

### 05 — TPS Demo

- [LICENSE.md](https://github.com/godotengine/tps-demo/blob/a82f15448e9b015440d3bbdf5e10801b260c4e9f/LICENSE.md): código sob texto MIT,
  copyright 2018–2021 Juan Linietsky e colaboradores Godot. Assets: CC-BY 3.0,
  Juan Linietsky/Fernando Miguel Calabró; música: CC-BY 3.0, Christian Fernando Perucchi.
  Há menção a materiais derivados de GameTextures.com: não presumir licença de
  arquivos originais nem importar mídia sem levantamento individual.
- Arquivos estudados: `LICENSE.md`, `project.godot`, `player/player.gd`.
  O código organiza `AnimationTree`, estados de caminhada/strafe/salto e componentes
  separados de input/modelo. Usar como referência de organização visual, mantendo FPS.
- **HEAD declara Godot 4.7, acima do Godot 4.4.1 do Suspeitos. Importação direta não é
  compatibilidade demonstrada.** A tag antiga `4.2-f0587b2` existe, mas não foi auditada;
  escolhê-la exigirá nova revisão de código/licença em seu próprio commit.
- Não copiar contratos multiplayer da demo: autoridade, direção de mira, sigilo de
  papéis e estado de morte precisam continuar regidos pelo servidor do Suspeitos.

### 06 — Wicked Engine

- [LICENSE.txt](https://github.com/turanszkij/WickedEngine/blob/79243b535c226b1612449335d632f225e2303258/LICENSE.txt): MIT,
  copyright 2026 Turánszki János. Não cobre indiscriminadamente dependências vendorizadas.
- Arquivos consultados: `README.md`, `LICENSE.txt`, `WickedEngine/wiRenderer.cpp`,
  `WickedEngine/wiScene.cpp`; árvore contém licenças adicionais de utilitários e conteúdo.
- Conceitos: organização de renderer, iluminação, sombras e cena. Aplicação futura
  pelo renderer/material/ambiente suportado pelo Godot, com benchmark pequeno antes.
- Compatibilidade: runtime C++17 com backend DirectX 12/Vulkan/Metal conforme plataforma,
  não addon Godot. Não importar runtime, shaders ou bibliotecas nativas. A licença MIT
  principal não é certificação das dependências, fontes, áudio ou modelos.

### 07 — ioquake3

- [COPYING.txt](https://github.com/ioquake/ioq3/blob/87a99d18206e878a20289f05ac3c16005dcae5c3/COPYING.txt): texto GPL v2.
  Cabeçalho de `code/client/cl_parse.c` declara copyright 1999–2005 Id Software,
  GPL v2 ou posterior. Alterações do projeto têm colaboradores próprios; preservar
  a distinção entre licença agregada e cabeçalho de cada arquivo.
- Arquivos consultados: `README.md`, `code/client/cl_parse.c`, `code/client/cl_input.c`,
  `code/server/sv_snapshot.c`, `code/server/sv_client.c`.
- Conceitos: snapshots aceitos somente após validação, sequências, confirmações,
  eventos confiáveis e mensagens antigas. Comparar com buffers e limites já existentes;
  SPEC 07 não deve recriar a predição analisada no SPEC 02.
- Compatibilidade: engine C independente; não integrar código, runtime ou protocolo.
  WebSocket/TCP do Suspeitos permanece padrão; eventual ENet/UDP exige proposta,
  infraestrutura e benchmark separados. Em TCP, perda de pacote não equivale a perda
  de mensagem de gameplay: testar atrasos/retransmissões e limites explicitamente.

## Rastreabilidade e limites

Consultas reproduzíveis, sem credenciais em documentação:

```sh
gh api repos/OWNER/REPO
gh api repos/OWNER/REPO/commits/BRANCH
gh api 'repos/OWNER/REPO/tags?per_page=3'
gh api 'repos/OWNER/REPO/git/trees/COMMIT?recursive=1'
gh api 'repos/OWNER/REPO/contents/CAMINHO?ref=COMMIT'
```

As sete árvores retornaram `truncated: false`. As consultas de tags mostraram as
primeiras três entradas, sem garantir ordem semântica de versão. Compatibilidade
foi analisada por manifesto, linguagem, arquitetura e documentação; **nenhuma
referência externa foi executada no Godot 4.4.1**. Não há inventário jurídico completo
por asset ou dependência porque nenhum será reutilizado no SPEC 00. Antes de qualquer
reuso em SPEC posterior, acrescentar uma linha com trecho/caminho original, SHA,
autoria, licença por arquivo, arquivo de destino, alterações e avisos preservados.

## Pendência de licenciamento já existente no baseline

Na inspeção dos arquivos versionados do Suspeitos não foi localizado um arquivo
`LICENSE`, `COPYING` ou equivalente que declare a licença do projeto. Isso não
impede documentar e testar o checkout autorizado, mas não permite certificar sua
licença de redistribuição nem presumir que código próprio e mídia sejam MIT.

`docs/decisions.md`, seção “Personagens GLB e aparência pública”, registra que os
oito modelos em `assets/characters/mystery_character_*.glb` vieram de
`personagem_3d`, branch `main`, pasta `models/`, gerados por
`tools/generate_characters.py`, sem recursos externos; a mesma seção informa que
o repositório de origem não declara licença. `client/arena_models.gd` confirma
o uso desses GLBs como apresentação. Os oito cabeçalhos glTF locais informam
`generator: Armed Mystery stdlib procedural source`, sem campo de copyright.
Essas evidências corroboram a origem procedural declarada, **não demonstram
licença ou autorização de redistribuição**; URL e commit da origem não estão
fixados nessa decisão histórica.

Nenhum modelo foi importado, alterado, removido ou publicado nesta tarefa.
Antes de nova incorporação ou publicação, o responsável deve registrar a URL,
commit de origem, autoria e permissão/licença dos GLBs e do gerador, além de
esclarecer a licença pretendida para o código do Suspeitos. Não há certificação
de direitos sobre os assets existentes neste SPEC 00.
