# Fase 2 — inventário técnico e de licenças das referências

Pesquisa por API do GitHub, com leitura dos arquivos de licença, README e manifests nas revisões abaixo; referências congeladas para esta missão. A consulta do código é estudo: **nenhum código, addon, binário, textura, modelo ou áudio desses oito projetos foi incorporado ao Suspeitos**. Nenhuma engine externa foi instalada. Uma licença de repositório não substitui a verificação do arquivo/asset individual nem de suas dependências.

Compatibilidade declarada significa o que os manifests/documentação dizem, **não** execução ou certificação do addon em nosso jogo. Os testes efetivamente executados pertencem aos relatórios dos SPECs. Os projetos externos não foram compilados. O alvo permanece Godot **4.4.1**, Compatibility, cliente Web/Windows e servidor Linux; as colisões compartilhadas continuam analíticas/determinísticas.

## Revisões consultadas

| Projeto | Versão/revisão | Commit integral | Código principal | Decisão nesta fase |
| --- | --- | --- | --- | --- |
| Godot Jolt | desenvolvimento (release disponível v0.16.0, SHA distinto) | `7f225894706bb923e9ab9e9c73152b71880c5a83` | MIT | Estudar; comparar backends nativos em laboratório, sem substituir a simulação compartilhada |
| Open 3D Engine | desenvolvimento, não uma release certificada | `2462b90ee389939336931a14e234fc4e3b4cd534` | Apache-2.0 **ou**, por opção, MIT | Estudar limites/componentização; reimplementar apenas conceitos necessários em Godot |
| Godot State Charts | plugin 0.22.5 | `76d226a3efac66a72aea825382b320c94808f409` | MIT | Estudar; manter estados visuais procedurais pequenos |
| Godot XR Tools | desenvolvimento, plugin 4.6.0 | `6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60` | MIT | Estudar interação/posse; reimplementar sem dependência XR |
| Dialogue Manager | desenvolvimento, plugin 4.1.0 | `7a72dcf64cfec8673d398606f2991d4cf81f2d11` | MIT | Descartar versão atual para 4.4.1; estudar v3.10.5 como opção futura |
| Terrain3D | desenvolvimento da linha 1.1.0-rc1 | `59bacc5e61aede7d0fd96ae9cd263f4cc0f09858` | MIT | Descartar integração na mansão; estudar para mapa externo futuro |
| The Dark Mod | desenvolvimento, sem release GitHub identificada | `4d0427244dd21951c74d22a33361517a220130ac` | GPL-3.0-or-later nas fontes consultadas | Estudo conceitual de informação sonora; não portar implementação ou assets |
| OpenMW | desenvolvimento, não release 0.51.0 | `6901b0a0da3187518801f932e69a1741273c1d5d` | GPLv3 (README e LICENSE) | Estudo conceitual de ações/contexto; não portar implementação ou assets |

### 1. Godot Jolt

Fontes: [README](https://github.com/godot-jolt/godot-jolt/blob/7f225894706bb923e9ab9e9c73152b71880c5a83/README.md), [MIT](https://github.com/godot-jolt/godot-jolt/blob/7f225894706bb923e9ab9e9c73152b71880c5a83/LICENSE.txt), [terceiros](https://github.com/godot-jolt/godot-jolt/blob/7f225894706bb923e9ab9e9c73152b71880c5a83/THIRDPARTY.txt), [projeto de exemplos](https://github.com/godot-jolt/godot-jolt/blob/7f225894706bb923e9ab9e9c73152b71880c5a83/examples/project.godot).

- **Compatibilidade:** README informa que Jolt foi integrado ao próprio Godot a partir de 4.4 e que a extensão suporta 4.3–4.6. O exemplo declara 4.3 e `Jolt Physics (Extension)`. Backend integrado e extensão são seletores distintos: não instalar uma GDExtension para testar o backend já incluído em 4.4.1. A existência e comportamento do backend neste binário precisam ser comprovados no laboratório; isso não certifica Jolt em todas as plataformas/export templates.
- **Licenças externas/assets:** THIRDPARTY identifica Godot Engine, godot-cpp, Jolt Physics e mimalloc sob termos MIT, cada qual com avisos próprios. Não foi feita liberação individual de todos os assets de exemplo; não os usar. A disponibilidade de binários não transfere uma certificação de Web/Windows ao nosso projeto.
- **Aproveitável:** avaliar queda, contato, repouso e custo de poucos corpos dinâmicos decorativos. Não confiar em sincronismo bit a bit de rigid bodies entre máquinas.
- **Alternativa nativa:** backend Godot Physics, RigidBody3D/StaticBody3D/PhysicsServer3D para laboratório; representação cinemática/analítica com autoridade do servidor para objetos que bloqueiam movimento ou tiros.
- **Custo:** extensão exige bibliotecas/exportações por plataforma, versões e avisos; rigid bodies ativos/contatos elevam CPU. Uma troca de backend global afetaria premissas existentes e tornaria replay/prediction mais difíceis. **Decisão:** estudar/comparar isoladamente; preservar colisão oficial determinística. Resultados do laboratório não são benchmarks de multiplayer por si sós.

### 2. Open 3D Engine

Fontes: [licenciamento](https://github.com/o3de/o3de/blob/2462b90ee389939336931a14e234fc4e3b4cd534/LICENSE.txt), [Apache-2.0](https://github.com/o3de/o3de/blob/2462b90ee389939336931a14e234fc4e3b4cd534/LICENSE_APACHE2.TXT), [MIT opcional](https://github.com/o3de/o3de/blob/2462b90ee389939336931a14e234fc4e3b4cd534/LICENSE_MIT.TXT), [README](https://github.com/o3de/o3de/blob/2462b90ee389939336931a14e234fc4e3b4cd534/README.md).

- **Compatibilidade:** engine C++ independente; não é addon nem componente executável no Godot 4.4.1. Não existe integração direta comprovada nesta pesquisa.
- **Licenças externas/assets:** LICENSE.txt permite Apache-2.0 ou MIT para a engine, mas exige termos separados para software/assets de terceiros. Cita explicitamente Qt sob LGPLv3 com exceções e a origem dos pacotes 3P; não considerar toda a árvore MIT. Não reutilizar demos/assets sem inventário específico.
- **Aproveitável:** separar definição estática de objeto, estado mutável e intenção validada; ownership e limites de simulação, sem copiar classes/implementações.
- **Alternativa nativa:** Resource/RefCounted, dicionários sanitizados, nós Godot e autoridade já existente (`MatchRoom`/`AuthoritativeWorld`).
- **Custo:** importar engine/SDK introduziria grande superfície C++, build, pacotes nativos e modelo de entidade diferente, sem benefício para a mansão. **Decisão:** estudo conceitual e implementação própria mínima, não instalação ou substituição do Godot.

### 3. Godot State Charts

Fontes: [MIT](https://github.com/derkork/godot-statecharts/blob/76d226a3efac66a72aea825382b320c94808f409/LICENSE), [README](https://github.com/derkork/godot-statecharts/blob/76d226a3efac66a72aea825382b320c94808f409/README.md), [plugin 0.22.5](https://github.com/derkork/godot-statecharts/blob/76d226a3efac66a72aea825382b320c94808f409/addons/godot_state_charts/plugin.cfg), [projeto](https://github.com/derkork/godot-statecharts/blob/76d226a3efac66a72aea825382b320c94808f409/project.godot), [licença dos ícones da demo](https://github.com/derkork/godot-statecharts/blob/76d226a3efac66a72aea825382b320c94808f409/godot_state_charts_examples/cooldown/LICENSE.md), [GUT](https://github.com/derkork/godot-statecharts/blob/76d226a3efac66a72aea825382b320c94808f409/addons/gut/LICENSE.md).

- **Compatibilidade:** projeto declara Godot 4.0/C#; isso coloca 4.4.1 dentro da família Godot 4, mas não prova que a revisão 0.22.5 inteira executa em 4.4.1. Biblioteca GDScript e exemplos C# devem ser avaliados separadamente se houver adoção futura; nesta fase não foram instalados nem executados.
- **Licenças externas/assets:** biblioteca MIT; GUT incluído tem MIT próprio; ícones J. W. Bjerk/eleazzaar da demo cooldown têm **CC BY 3.0**, não MIT. Não copiar a demo como se todos os seus recursos fossem MIT.
- **Aproveitável:** transições explícitas, prioridade de morte/interrupção, separação entre estado visual e oficial. Não fazer state chart cosmético conceder ações ou dano.
- **Alternativa nativa:** enum/estado procedural com timers em `CharacterAnimator`, AnimationPlayer/AnimationTree quando o número de clips justificar. Reutilizar os rigs atuais.
- **Custo:** plugin e nós adicionais, aprendizado, migração/serialização de gráficos e duplicação do estado servidor. **Decisão:** estudar; manter a solução procedural para o pequeno conjunto de estados atual. Não instalar só para representar idle/walk/fire/death.

### 4. Godot XR Tools

Fontes: [README e tabela de compatibilidade](https://github.com/GodotVR/godot-xr-tools/blob/6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60/README.md), [MIT](https://github.com/GodotVR/godot-xr-tools/blob/6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60/LICENSE), [projeto 4.4](https://github.com/GodotVR/godot-xr-tools/blob/6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60/project.godot), [plugin de desenvolvimento 4.6.0](https://github.com/GodotVR/godot-xr-tools/blob/6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60/addons/godot-xr-tools/plugin.cfg).

- **Compatibilidade:** tabela do README informa XR Tools 4.5.x exige Godot 4.4; 4.4.x exige 4.2. O commit consultado já declara plugin 4.6.0 enquanto o projeto declara engine 4.4; não equiparar esses números de versão. Não certificamos este desenvolvimento nem importamos dependências XR para um FPS sem XR.
- **Licenças externas/assets:** código MIT; README diz imagens CC0 salvo indicação. [Mãos](https://github.com/GodotVR/godot-xr-tools/blob/6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60/addons/godot-xr-tools/hands/License.md) e [ícones](https://github.com/GodotVR/godot-xr-tools/blob/6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60/addons/godot-xr-tools/editor/icons/LICENSE) têm CC0; [freesound](https://github.com/GodotVR/godot-xr-tools/blob/6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60/assets/freesound/License.txt), [Bryan Teoh](https://github.com/GodotVR/godot-xr-tools/blob/6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60/assets/BryanTeoh/License.txt) e [DigitalN8m4r3](https://github.com/GodotVR/godot-xr-tools/blob/6c6189bdfcdf855052ef1aeb9f3e0ec4c7a7eb60/assets/digitaln8m4r3/License.txt) possuem avisos CC0 individuais. Isso não é auditoria de todos os assets; nenhum foi aproveitado.
- **Aproveitável:** conceitos de objeto pegável, exclusividade de quem segura e interrupção/soltura. Interações desktop devem continuar intenções verificadas no servidor, sem enviar transform livre do objeto.
- **Alternativa nativa:** ray/alcance com input E, estado de posse por peer e transform derivado da posição oficial; StaticBody3D/representação analítica para colisão.
- **Custo:** XR introduz poses/controladores/rigs e pressupostos de interação ausentes no jogo; replicar física de mãos seria custo desnecessário. **Decisão:** estudo conceitual; implementar interações próprias sem XR Tools.

### 5. Dialogue Manager

Fontes atuais: [README](https://github.com/nathanhoad/godot_dialogue_manager/blob/7a72dcf64cfec8673d398606f2991d4cf81f2d11/README.md), [MIT](https://github.com/nathanhoad/godot_dialogue_manager/blob/7a72dcf64cfec8673d398606f2991d4cf81f2d11/LICENSE), [plugin 4.1.0](https://github.com/nathanhoad/godot_dialogue_manager/blob/7a72dcf64cfec8673d398606f2991d4cf81f2d11/addons/dialogue_manager/plugin.cfg).

- **Compatibilidade:** versão atual exige **Godot 4.6+**, incompatível com 4.4.1. O próprio README indica a linha 3.10 para 4.4/4.5. Alternativa examinada: **v3.10.5**, commit `0049d4d14f62aeb6377be8e6529d12e8e256ef27`; [README congelado](https://github.com/nathanhoad/godot_dialogue_manager/blob/0049d4d14f62aeb6377be8e6529d12e8e256ef27/README.md) diz 4.4+, [plugin](https://github.com/nathanhoad/godot_dialogue_manager/blob/0049d4d14f62aeb6377be8e6529d12e8e256ef27/addons/dialogue_manager/plugin.cfg) confirma 3.10.5. Porém seu [projeto de testes](https://github.com/nathanhoad/godot_dialogue_manager/blob/0049d4d14f62aeb6377be8e6529d12e8e256ef27/project.godot) declara 4.7/C#. A promessa de compatibilidade do addon não certifica esse harness inteiro em 4.4.1; adoção futura exige teste mínimo do addon isolado no engine fixado.
- **Licenças externas/assets:** código MIT; screenshots, links para projetos-exemplo e conteúdo de terceiros não recebem autorização automática por estarem no README. Não foram importados. Validar recursos por arquivo em qualquer adoção futura.
- **Aproveitável:** apresentar texto contextual a partir de estado autorizado, sem execução de regras de papel pelo script de diálogo. Diálogo por cliente não é fonte de verdade multiplayer.
- **Alternativa nativa:** Label/Control e catálogo de mensagens com IDs de evidência, dados sanitizados e decisão servidor; suficientes para inspeção de corpos e feedback atual.
- **Custo:** parser/editor, recursos, traduções, autoload, callbacks e eventual C# de exemplos aumentam manutenção e superfície de autoridade. **Decisão:** não instalar na fase 2; documentar a opção v3 compatível declarada para futura necessidade real de diálogo. Sem NPC, serviço pago ou LLM.

### 6. Terrain3D

Fontes: [MIT](https://github.com/TokisanGames/Terrain3D/blob/59bacc5e61aede7d0fd96ae9cd263f4cc0f09858/LICENSE.txt), [README](https://github.com/TokisanGames/Terrain3D/blob/59bacc5e61aede7d0fd96ae9cd263f4cc0f09858/README.md), [manifest atual](https://github.com/TokisanGames/Terrain3D/blob/59bacc5e61aede7d0fd96ae9cd263f4cc0f09858/project/addons/terrain_3d/terrain.gdextension), [texturas da demo](https://github.com/TokisanGames/Terrain3D/blob/59bacc5e61aede7d0fd96ae9cd263f4cc0f09858/project/demo/assets/textures/asset_licenses.txt), [godot-cpp](https://github.com/TokisanGames/Terrain3D/blob/59bacc5e61aede7d0fd96ae9cd263f4cc0f09858/.gitmodules).

- **Compatibilidade:** manifest atual tem `compatibility_minimum = 4.5`, portanto não serve ao alvo 4.4.1. Alternativa histórica **v1.0.1-stable**, commit `630eb4179d2daf4a262b0b34fd3b9415f81ab43a`: [manifest](https://github.com/TokisanGames/Terrain3D/blob/630eb4179d2daf4a262b0b34fd3b9415f81ab43a/project/addons/terrain_3d/terrain.gdextension) explicita mínimo 4.4 e bibliotecas por plataforma, inclusive Web. É elegibilidade de versão, não garantia de suporte a todas as opções de renderização ou aprovação do build aqui.
- **Licenças externas/assets:** addon MIT, integração com godot-cpp (verificar revisão/licença no momento de compilar); texturas ambientCG Ground037/Rock030/Rock023 da demo têm aviso CC0. Não estender esse aviso indiscriminadamente à árvore de assets. Nenhum material reutilizado.
- **Aproveitável:** avaliar futuramente streaming/LOD de terreno exterior, separado da topologia e colisão oficial da mansão.
- **Alternativa nativa:** manter `MansionMap`/malhas atuais, colliders simples e interação discreta. Não há necessidade de heightmap ou streaming no interior.
- **Custo:** GDExtension C++, binários por plataforma, memória de heightmaps/materials, LOD/streaming e novo modelo de colisão. **Decisão:** não integrar neste mapa; registrar alternativa histórica se surgir um projeto de mapa externo, com avaliação própria de renderer/Web/autoridade.

### 7. The Dark Mod

Fontes: [licença de assets e exceções](https://github.com/stgatilov/darkmod_src/blob/4d0427244dd21951c74d22a33361517a220130ac/LICENSE.txt), [cabeçalho GPL do sistema de som](https://github.com/stgatilov/darkmod_src/blob/4d0427244dd21951c74d22a33361517a220130ac/game/SndProp.h), [documentação do repositório](https://github.com/stgatilov/darkmod_src/blob/4d0427244dd21951c74d22a33361517a220130ac/.github/README.md), [dependências](https://github.com/stgatilov/darkmod_src/blob/4d0427244dd21951c74d22a33361517a220130ac/ThirdParty/readme.md), [pacotes](https://github.com/stgatilov/darkmod_src/blob/4d0427244dd21951c74d22a33361517a220130ac/ThirdParty/packages.yml).

- **Compatibilidade:** engine C++ derivada de Doom 3; não é addon Godot nem sistema diretamente compatível com 4.4.1. O modelo de portal/área não pode ser transplantado como se nossa mansão tivesse a mesma estrutura.
- **Licenças externas/assets:** cabeçalho de SndProp declara **GPLv3 ou posterior**. LICENSE.txt diz, por padrão, conteúdo não-software sob **CC BY-NC-SA 3.0**, missões de autores com permissões específicas e texturas cgtextures com restrição de redistribuição. A API GitHub não classifica a licença corretamente como um SPDX único, portanto ela não foi usada como prova. Bibliotecas de terceiros possuem termos separados; nenhuma lib foi importada.
- **Aproveitável:** conceito de informação sonora contextual: distância, obstáculo/porta, ação suspeita e prioridade. Não copiar o algoritmo de propagação, fórmulas específicas, código ou assets sonoros.
- **Alternativa nativa:** AudioStreamPlayer3D, catálogo sonoro gerado/próprio, eventos autorizados e uma consulta limitada de linha/obstáculo opcional. A oclusão básica não é simulação acústica por portais.
- **Custo:** propagação avançada por áreas/portais exige representação e manutenção do mapa, cache e orçamento de consultas; pode custar CPU e revelar eventos se a autorização for mal desenhada. **Decisão:** estudo conceitual, implementação independente simples. Rejeitar importação de código GPL e assets restritos.

### 8. OpenMW

Fontes: [README](https://github.com/OpenMW/openmw/blob/6901b0a0da3187518801f932e69a1741273c1d5d/README.md), [GPLv3](https://github.com/OpenMW/openmw/blob/6901b0a0da3187518801f932e69a1741273c1d5d/LICENSE), [licença de scripts CMake derivados](https://github.com/OpenMW/openmw/blob/6901b0a0da3187518801f932e69a1741273c1d5d/cmake/COPYING-CMAKE-SCRIPTS). A separação de ações contextuais é visível na árvore `apps/openmw/mwworld/` (`actionread`, `actiontake`, `actiontalk`); não foi portado código desses arquivos.

- **Compatibilidade:** engine RPG C++ independente, não plugin Godot 4.4.1. Nem a autoridade nem as regras de Morrowind se aplicam automaticamente ao multiplayer social do Suspeitos.
- **Licenças externas/assets:** README identifica engine GPLv3, fontes DejaVu sob licença própria e DemonicLetters/MysticCards sob SIL OFL. Scripts CMake específicos têm aviso BSD de três cláusulas. O README também exige propriedade do Morrowind para jogar seu conteúdo: engine livre **não** libera assets comerciais da Bethesda. Nenhum conteúdo de jogo, fonte ou código foi reutilizado.
- **Aproveitável:** separar ação contextual e resultado apresentado; investigação lê evidência sanitizada, sem expor papel do alvo. Identificador de objeto estável e validação de disponibilidade/alcance são conceitos genéricos implementados independentemente.
- **Alternativa nativa:** `BodyRegistry`/`BodyRules` existentes, autoridade de interação e resposta privada com allowlist; enum de intenção em vez de infraestrutura RPG/scripting.
- **Custo:** portar sistema de inventário/diálogo/IA amplo exigiria outra engine, grandes dependências e revisão de licenças; não é justificável para inspeção simples. **Decisão:** estudar arquitetura conceitual, sem portar GPL ou NPCs ao modo principal.

## Aplicação e limites da pesquisa

1. As dependências de produção existentes permanecem as do projeto/Godot 4.4.1. Não adicionar os oito projetos ao `addons/`, não mudar engine/backend global e não importar exemplos.
2. As implementações de fase 2 são próprias, escritas para os contratos existentes e testadas como alterações do Suspeitos. MIT/Apache permissivos não são motivo suficiente para copiar uma engine completa.
3. Jolt nativo pode ser comparado com Godot Physics somente em laboratório isolado; eventos/estados competitivos continuam oficiais no servidor. A existência do backend e suas medições devem aparecer no relatório de laboratório, sem declarar sucesso não executado.
4. State Charts, Dialogue Manager e Terrain3D continuam opções futuras, condicionadas a necessidade, versão fixada, teste de integração, auditoria de assets e plataformas. A avaliação documental do SPEC 14 é uma entrega válida, não promessa de NPC pronto.
5. O inventário não concede licenças aos assets pré-existentes do Suspeitos: a pendência de procedência registrada na auditoria dos SPECs 00–08 permanece separada. Nenhuma confirmação de licença aqui deve ser estendida a esses assets.
