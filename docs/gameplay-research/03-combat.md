# SPEC 03 — catálogo e composição do combate

`server/weapon_catalog.gd` expõe `WeaponCatalog.defaults() -> Dictionary`.
Cada chamada cria um dicionário e uma `WeaponDefinition` novos, contendo somente
`common_pistol`: dano 34, pente 6, reserva máxima 18, intervalo 400 ms, alcance
20 m, recarga 1200 ms e spread 0. O caminho normal de servidor usa essa fábrica.

A composição aceita:

```gdscript
CombatAuthority.new(rounds: RoundAuthority, authoritative_world: AuthoritativeWorld,
    weapon_definitions: Dictionary = {}, rng: RandomNumberGenerator = null)
```

Dois argumentos preservam o comportamento anterior. Dicionário vazio seleciona
os defaults. Um catálogo não vazio é configuração explícita do servidor:
`InventoryAuthority` filtra com `WeaponRules.validate_definition` e igualdade
entre chave e id; copia os oito campos escalares validados para instâncias próprias.
Alterações posteriores no dicionário ou na definição do chamador não afetam a
autoridade nem outra instância de inventário. Referências retornadas pelas APIs
internas continuam mutáveis e pertencem exclusivamente ao servidor confiável.
Um catálogo explícito inteiramente inválido fica sem armas; não há fallback.
O RNG opcional é encaminhado ao `CombatRules` existente; o servidor é seu dono.
Nenhum RPC aceita catálogo, definição ou seed.

O mapa mantém seus pickups e valores de munição: armas são `common_pistol`,
pente inicial 6 limitado pela capacidade configurada, reserva inicial 0; caixas
continuam iguais. Um catálogo sem `common_pistol` não gera pickups de arma nesse
mapa. Injetar catálogos em produção exige configuração compatível com o mapa;
não há seleção de armas ou slots adicionais.

Disparo, hitscan, dano e eliminação permanecem nas autoridades existentes.
A resolução no mesmo tick é sequencial: o primeiro disparo processado pode matar
o segundo atirador, cujo comando posterior é rejeitado sem consumir munição ou
emitir tiro. Isso não promete justiça de ordem entre peers nem simultaneidade.
Se uma eliminação encerra a rodada, o gate de rodada inativa tem precedência.
A duplicação de sequência aceita não repete munição, dano ou evento público.

Testes em Godot 4.4.1: `weapon_catalog_test.gd` verifica defaults exatos,
validação e isolamento; `combat_authority_test.gd` mantém as assertivas antigas e
acrescenta duplicação, ordem letal nas duas direções, capacidade/dano/alcance/cadência
injetados e catálogo inválido sem fallback. Suítes de armas, inventário, regras de
combate, coordenador e rodadas fazem parte da regressão; o harness
`tests/combat_network_test.sh` verifica servidor + 4 clientes e
`COMBAT_CLIENTS=8 COMBAT_EXTENDED=true` verifica sala cheia e reset, com sigilo e
shutdown coordenado. Evidências e saídas ficam no relatório externo da missão.

Referência conceitual: [Red Eclipse](https://github.com/redeclipse/base/tree/21bd045fd76e0bf50a4e0205300d599bff182369),
SHA `21bd045fd76e0bf50a4e0205300d599bff182369`, separação entre configuração,
estado de arma e apresentação. Fontes sob zlib conforme `doc/license.txt`;
assets têm licenças próprias. Nenhum código, asset ou engine externo foi copiado,
traduzido ou incorporado. Ver `license-register.md`.

Limites: somente pistola comum, dano independente de papel, sem armas especiais,
headshot, ressurreição, projétil, rewind ou mudança de protocolo. Calibração de
spread/recoil e avaliação visual pertencem aos próximos SPECs.
