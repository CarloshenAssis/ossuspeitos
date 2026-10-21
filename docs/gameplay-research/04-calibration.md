# SPEC 04 — precisão autoritativa e laboratório

Implementado em 2026-10-21 sobre o catálogo do SPEC03. Não há segunda trajetória no cliente: `CombatRules` produz a direção, `CombatAuthority` resolve parede/piso/jogador/alcance e o evento oficial conserva origem e fim. Nenhuma mudança de pacote ou DTO; yaw/pitch oficiais não recebem recoil.

## Configuração e fórmula

Os oito argumentos originais de `WeaponDefinition` permanecem posicionais e compatíveis. Quatro argumentos opcionais acrescentados ao final são copiados para o catálogo pertencente ao inventário:

| Campo | Default comum | Laboratório/testes |
| --- | ---: | ---: |
| `spread_radians` (já existente) | 0 | 0 |
| `movement_spread_radians` | 0 | 0,1 rad |
| `bloom_per_shot_radians` | 0 | 0,02 rad |
| `max_bloom_radians` | 0 | 0,05 rad |
| `bloom_recovery_radians_per_second` | 0 | 0,01 rad/s |

Para um disparo aceito no tempo servidor `t`, com último disparo `t0`:

```text
b = max(0, bloom_anterior - max(0, t - t0) * recuperação / 1000)
f = clamp(length(velocity.xz) / MovementRules.MAX_SPEED, 0, 1)
cone = spread_base + movimento * f + b
bloom_armazenado = min(cap, b + incremento)
```

Primeiro disparo usa bloom zero; incremento afeta os seguintes. Com o exemplo acima, em 1000 ms o tiro parado é exato e armazena 0,02; em 1400 ms usa 0,016 e armazena 0,036. Recuperação até zero é exata após 5000 ms para bloom 0,05. Recarga não precisa de relógio próprio: o intervalo entre disparos inclui seu tempo. O cálculo é preguiçoso, apenas no próximo disparo aceito; uma recusa não muda munição, bloom, sequência, tempo ou RNG.

Velocidade é a oficial anterior ao movimento daquele comando: o mundo aplica mira, executa ação e depois move. Iniciar movimento e disparar no mesmo comando ainda usa velocidade anterior zero. Y não entra na fração. `MAX_SPEED=5` é o envelope de compatibilidade existente; a configuração de movimento não expõe accessor público de velocidade ativa. Reduzir futuramente a velocidade configurada não aumenta essa fração automaticamente.

Contexto interno sem `velocity` continua equivalente a zero; valor presente exige Vector3 finito. Cliente não pode informar velocidade, spread ou seed no intent. Campos novos exigem número finito não negativo (bool/string/null recusados); incremento ≤ cap; cap positivo exige recuperação positiva. Com spread dinâmico, base + movimento + cap ≤ PI/4. Há motivos distintos de rejeição em `WeaponRules`; nenhuma configuração inválida entra no catálogo.

## Correção do cone estático completo

O teste vermelho preservado demonstrou que `sqrt(u) * tan(cone)` invertia/encolhia cones acima de PI/2; PI não incluía a semiesfera traseira. A amostragem foi substituída por uma construção própria de calota esférica: `a = lerp(1, cos(cone), u)`, `r = sqrt(max(0, 1-a²))`, azimute uniforme em `[0, TAU]`, direção `a*d + r*cos(az)*t + r*sin(az)*b`. Ela é uniforme em ângulo sólido e finita de zero a PI, mantendo a faixa estática anteriormente aceita. Cone zero não consome RNG; positivo usa dois sorteios. Mesma seed e agenda reproduzem a mesma trajetória nesta implementação; distribuições antigas de spread não zero mudam intencionalmente. A pistola comum continua exatamente sem spread.

## Executar o laboratório

```bash
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
DISPLAY=:99 "$GODOT_BIN" --audio-driver Dummy --path . tests/scenes/gunplay_lab.tscn
# Execução curta automatizada: acrescentar -- --lab-smoke
"$GODOT_BIN" --headless --path . --script tests/gunplay_test.gd
```

Cena isolada, seed 481, catálogo real com override somente local: dano zero, carregador 24, demais valores comuns e precisão da tabela. O pickup adicional de laboratório usa `InventoryAuthority.add_ground_weapon`; os pickups da mansão conservam seis cartuchos. Doze disparos em tempos explícitos: seis parados, cinco com velocidade oficial 5 e um parado após recuperação em 12000 ms. Amarelo/laranja/verde distinguem fases. Alvos procedurais mostram AABBs oficiais; obstáculos leem `MansionMap.blockers()` da região central, sem tetos para observação. Colisão real continua a mansão completa, não a decoração do laboratório. Não substitui mapa ou controller de produção.

Linhas e marcadores usam somente os endpoints oficiais, sem raycast visual. A cena altera um transform de câmera local antes de atirar, verifica yaw/pitch oficiais intactos e o retorno ao endpoint inicial após recuperação. `combat_feedback_test` também mantém a asserção do recoil real de `ArenaView` não alterar a mira. A cena imprime `GUNPLAY_LAB_OK shots=12 seed=481 official_aim_error=0`; Esc sai.

## Evidências e limites

Logs em `/workspace/.ossuspeitos-state/mission-sdd/spec04/`: vermelho original (`red.log`), verdes inicial/expandido e execução final `gunplay.log` com **6216 verificações**. Cobertura: seed, cones perto de PI/2 e em PI, distribuição angular, validação/clone, cliente seed proibido, movimento/saturação, bloom/cap/recuperação/recarga, rejeição pura, isolamento por jogador/sala/reset/rodada e autoridade de piso/parede/alcance/ordem causal.

Suítes aprovadas: weapon_rules 27, weapon_catalog 9, inventory_authority 23, combat_rules 25, combat_authority 86, round_rules 63, round_authority 192, netcode 266 e combat_feedback 84. O último conserva warnings de ownership e quatro erros `look_at` fora da árvore, também presentes no baseline SPEC03; a execução atual também avisou sobre instâncias no encerramento. Esses diagnósticos não são certificados como corrigidos aqui.

Rede real: `COMBAT_NETWORK_TEST_OK server=1 clients=4 extended=false` na repetição sequencial; `server=1 clients=8 extended=true` com shutdown completo dos oito clientes, privacidade e reset da próxima rodada. A primeira execução de quatro clientes, iniciada em paralelo com outras verificações, falhou por timeout no estágio CONTEST: peers confirmados, nenhuma ação recebida. A repetição passou sem alterar código/teste; a causa do comportamento intermitente não foi demonstrada e permanece registrada em `network4-summary.log`, com sucesso em `network4-retry-summary.log`.

Laboratório executado headless e graficamente no Godot 4.4.1, Compatibility/OpenGL 4.5 Mesa llvmpipe, DISPLAY=:99, áudio Dummy; ambos produziram o marker esperado. Driver gráfico avisou que VSync não é suportado. Essa execução comprova carregamento/renderização e invariantes automatizados, não aprovação humana de sensação de tiro nem desempenho em GPU/Android/Web. Não houve benchmark de FPS. Produção mantém parâmetros novos zero; recoil visual adicional pertence ao SPEC05. Não foram adicionados projéteis, penetração, rewind, regras de papéis ou assets/código externo.
