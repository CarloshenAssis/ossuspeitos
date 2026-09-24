# Rede em tempo real — nota técnica da fase 4

Nota escrita **antes** da implementação da fase 4, a partir do código da main
`7c98bd9` (fase 3 integrada). A seção 1 descreve o estado encontrado; a seção 2,
a linha de base medida; a seção 3, a tabela de parâmetros decidida antes de
implementar. O resultado da implementação fica nas seções 4 em diante.

## 1. Estado encontrado (protocolo 8)

### Fluxo real

```
mouse/teclado ──_unhandled_input──▶ pending_yaw/pitch (±0,35 rad por janela; excesso perdido)
                 _process a cada ≥50 ms (acumulador de quadro) ──▶ submit_input(seq, move, dyaw, dpitch)
servidor: submit_input ao chegar ──▶ accept_input: aplica yaw/pitch já, guarda `input` de movimento
servidor: _physics_process 60 Hz ──▶ integrate(estado, 1/60) de TODOS com o último `input`
                                      (vale por até 300 ms sem novo pacote)
servidor: a cada 3 ticks ──▶ world_snapshot.rpc(estados públicos) para todos
cliente: world_snapshot ──▶ ArenaView.apply_snapshot
         próprio jogador: _place_rig escreve posição/yaw do rig e pitch da câmera (sem previsão)
         remotos: guarda o último estado; _process faz lerp exponencial (1−e^(−12·dt)); salta > 2,5 m
clique ──▶ request_fire(seq_tiro, origem_câmera, direção_câmera) reliable, imediato
servidor: request_fire ao chegar ──▶ valida rumo ±70° do yaw oficial e ±25° do pitch oficial;
         raio com rumo horizontal DECLARADO e pitch oficial, origem no olho oficial
```

### Frequências

- Renderização sem limite próprio (vsync do sistema). Sob xvfb/llvmpipe, a
  640×360, medimos quadros de cerca de 40 ms.
- Física de 60 Hz no servidor e no cliente (padrão do projeto, 8 passos por
  quadro no máximo).
- Envio de input a cada quadro que passa de 50 ms desde o último envio (≤ 20 Hz,
  quantizado pelo quadro).
- Snapshot a cada 3 ticks (20 Hz), o mesmo payload para todos.

### Semântica de yaw e pitch

- Ambos vão como **deltas** em radianos por envio.
- Yaw 0 olha para −Z e cresce no sentido anti-horário visto de cima. Mouse para a
  direita (relative.x > 0) reduz o yaw.
- Pitch positivo olha para cima; mouse para cima aumenta o pitch.
- Sensibilidade: 0,0025 rad/pixel.
- Limites:
  - no cliente, cada eixo é limitado a ±0,35 rad por janela de envio, e o
    excesso se perde;
  - no servidor, cada delta é limitado a ±0,35 rad por pacote, com balde de taxa
    de 3 rad/s e rajada de 0,7 rad por eixo, reabastecido pelo relógio de
    chegada;
  - acima disso o pacote inteiro é recusado, movimento incluído.
- O pitch oficial fica em ±75°; a cabeça dos avatares é limitada, só na
  aparência, a ±40°.

### Transporte

- `WebSocketMultiplayerPeer` (TCP), com relay desligado.
- `submit_input` e `world_snapshot` são declarados `unreliable_ordered`, e o
  resto é `reliable`. No WebSocket todo canal é entregue em ordem e sem perda,
  pelo mesmo fluxo.

### Correlação de movimento e ações

- `submit_input` tem sequência monotônica por conexão, e uma recusa consome a
  sequência.
- Coleta, tiro e recarga são RPCs separadas, com sequência independente por
  ação, validadas **na chegada**. O servidor zera a sequência a cada rodada; o
  cliente nunca zera. Com salto máximo de 64, depois de 63 ações de um tipo na
  sessão, essa ação passa a ser recusada (`sequence_jump`) nas rodadas
  seguintes. É um defeito real, corrigido na fase 4.
- **Defeito central de ordem:** o delta de mira fica retido até 50 ms no
  cliente, mas o clique sai na hora. O servidor atira com o yaw anterior ao
  movimento do mouse que o jogador já via, sem avisar.

### Quem escreve cada transform

| Nó | Quem escreve |
| --- | --- |
| rig local (posição e yaw) e pitch da câmera | `ArenaView._place_rig`, em snapshots e ao sair do espectador |
| avatar remoto (posição e yaw), cabeça | `ArenaView._process` (lerp) |
| pivôs e altura do `CharacterModel` | `CharacterAnimator` |
| `WeaponPivot` | tweens de recuo e recarga |
| `v_offset`/`h_offset` da câmera | tranco de dano |

### Transições

- **Nova rodada:** as posições **não** são reiniciadas (regra atual); o combate é
  recriado; o cliente limpa o estado de combate no WAITING/COUNTDOWN.
- **Eliminação:** o servidor zera input e velocidade, o avatar some e o
  espectador segue o snapshot do alvo.
- **Desconexão:** o servidor remove o jogador do mundo; o cliente interativo
  recarrega a cena (estado novo).
- **Shutdown:** encerramento em duas fases.

### Previsão e interpolação existentes

- Não há previsão local.
- A interpolação remota é o lerp exponencial descrito acima. Ela suaviza, mas não
  apresenta um instante coerente e cai no próximo snapshot com atraso variável.

## 2. Linha de base medida (código da main `7c98bd9`)

**Método:** `tests/latency_probe.sh`.
- Composição: servidor headless, dois clientes headless parados (para a rodada
  entrar em ACTIVE) e dois clientes gráficos (observador e "mover") sob xvfb, a
  640×360.
- A entrada passa pelo caminho normal (`Input.parse_input_event` e
  `Input.action_press`).
- O tempo vai do evento consumido até o fim do desenho do quadro que já mostra o
  efeito (`RenderingServer.frame_post_draw`). Não é latência física
  mouse→monitor.
- Mouse: 24 amostras de 40 px. Tecla: 12 amostras.
- Suavidade remota: velocidade apresentada do avatar do "mover" por quadro,
  enquanto a velocidade oficial passa de 3 m/s.
- Atraso: `tests/net_delay_peer.gd` (atraso de aplicação só de teste, veja 3.3)
  nos dois clientes gráficos.
- Ambiente: contêiner com 4 vCPU Intel Xeon 2,8 GHz, 15 GB, Godot 4.4.1,
  renderização por software (llvmpipe). O quadro médio fica em torno de 41 ms,
  o que domina todas as medidas.

| Perfil (seed 1) | Atraso efetivo por sentido, p50/p95 | Mouse → quadro, p50/p95/máx | Tecla → quadro, p50/p95/máx | Velocidade remota, CV |
| --- | --- | --- | --- | --- |
| local (0 ms) | 0/0 | 145 / 187 / 208 ms | 159 / 216 / 216 ms | 0,31 |
| RTT-alvo 80 ms (40+40) | 50/85 | 277 / 315 / 320 ms | 300 / 372 / 372 ms | 0,39 |
| RTT-alvo 150 ms (65+65, jitter 0–20 ms) | 86/120 | 326 / 375 / 413 ms | 362 / 384 / 384 ms | 0,33 |

- O atraso efetivo passa do configurado porque a fila só é lida uma vez por
  quadro (~40 ms).
- Não há correções locais na linha de base: sem previsão, nada a corrigir. A
  câmera espera a volta completa.

## 3. Parâmetros decididos antes da implementação

Constantes centralizadas em `shared/net_sync.gd`; os limites existentes de
movimento e mira continuam em `MovementRules`.

| Parâmetro | Valor | Justificativa |
| --- | --- | --- |
| Tick de simulação | 60 Hz, dt fixo 1/60 | a física do servidor já é 60 Hz; o cliente usa o mesmo passo |
| Duração de um comando | 1 tick (definida pelo servidor, não viaja no pacote) | o cliente não escolhe dt |
| Envio de comandos | a cada 2 ticks (30 pacotes/s) e na hora quando há ação | igual ao `MAX_COMMAND_RATE` atual; ação não espera |
| Comandos por pacote | ≤ 8 | recuperação após um quadro longo (até 8 passos de física) |
| Fila no servidor | ≤ 32 comandos (~0,53 s) | cobre jitter e rajadas; o excesso é recusado explicitamente |
| Consumo por tick | 1; até 4 quando a fila passa de 3 | movimento oficial uniforme para quem observa; alcança rajadas |
| Orçamento de tempo | +1 tick por tick, teto de 12 | mais pacotes não dão mais tempo de simulação |
| Taxa de pacotes | balde de 60/s com rajada de 16 | só barra inundação; jitter legítimo passa |
| Salto de sequência | ≤ 64 (valor atual) | lacuna vira perda declarada |
| Limite de yaw/pitch | 0,35 rad por comando; balde de 3 rad/s com rajada de 0,7 (valores atuais) | agora reabastecido por tick simulado, então o cliente prevê exatamente o que o servidor aceita |
| Snapshot | a cada 3 ticks (20 Hz, atual), por destinatário, com tick e ACK | o ACK é privado de cada jogador |
| Pendentes no cliente | ≤ 90 comandos (1,5 s) | acima disso, recuperação explícita pelo estado oficial |
| Correção de posição | < 1 cm: aplica direto; 1 cm a 1 m: offset visual com τ 0,1 s, no máximo 0,25 s; ≥ 1 m ou nova época: salto | offset nunca atravessa parede (verificado na geometria oficial) |
| Correção de mira | < 0,002 rad: direto; até 0,1 rad: τ 0,05 s, no máximo 0,15 s; maior: salto | a mira é determinística; só diverge quando o servidor a impõe |
| Atraso de interpolação | 6 ticks (100 ms = 2 snapshots) + jitter estimado, limitado a +6 | com um snapshot perdido ou atrasado ainda há amostra futura |
| Ajuste do relógio de apresentação | ±10% da taxa; ressincroniza acima de 30 ticks de erro | sem acelerações visuais bruscas |
| Extrapolação | até 6 ticks (100 ms) com a colisão oficial; depois segura | não anda para sempre após stall ou desconexão |
| Buffer remoto | ≤ 32 amostras (1,6 s) | limitado |
| Prazo de convergência (gate) | ≤ 1,0 s após o input parar e a rede estabilizar | RTT de 150 ms + jitter de 40 ms + snapshot de 50 ms + fila de 50 ms + suavização de 250 ms ≈ 0,54 s, com folga |
| Tolerância previsto × oficial | 1 mm de posição e 1e-4 rad (sem correção de servidor) | mesmo integrador e mesmos valores de 32 bits; a folga cobre arredondamento de Vector3 |

### 3.1. Contrato de comandos (protocolo 9)

- **Pacote:** `submit_commands([epoch, first_seq, [comando…]])`.
- **Comando:** `[move_x, move_y, dyaw, dpitch, ação]`.
- **Ação:** `[]`, `["fire", id]`, `["reload", id]` ou `["pickup", id, pickup_id]`.
- **Sequência:** 1, 2, 3… por conexão (inteiro de 64 bits; o reinício só acontece
  numa conexão nova).
- **Época de controle:**
  - vem do servidor e aumenta na entrada da rodada, na eliminação e em
    reposicionamento de teste;
  - um comando de época antiga é resolvido como recusado, e sua ação recebe
    resultado explícito.
- **Ordem causal:**
  1. aplica a mira do comando;
  2. executa a ação com a posição e a mira oficiais daquele ponto;
  3. integra o movimento do tick.

  O clique fecha o comando com os deltas de mouse recebidos antes dele; o que
  chega depois vai para o comando seguinte. Não há fila de dependência à parte:
  a ação está no próprio fluxo ordenado.
- **ACK** no snapshot de cada destinatário: `last_resolved` (todos os comandos
  ≤ N foram aplicados, recusados ou declarados perdidos), a época e os baldes de
  mira oficiais daquele ponto.
- **Tiro:**
  - a origem é o olho oficial;
  - a direção sai de `aim_direction(yaw, pitch)` oficiais depois da mira do
    comando;
  - não há mais direção declarada no fio;
  - a identidade da ação é (rodada, id); o id recomeça em cada rodada no cliente.

### 3.2. Domínios de estado

1. **Oficial:** servidor e snapshots.
2. **Previsto:** oficial no ACK + replay dos comandos pendentes (`PlayerPrediction`).
3. **Apresentação:** previsto interpolado entre ticks + mouse ainda não
   comandado + offset de correção.

`ArenaView` é o único escritor do rig local e dos avatares, uma vez por quadro.

### 3.3. Atraso de teste

- `tests/net_delay_peer.gd` envolve o `MultiplayerPeer` do cliente e segura cada
  pacote numa fila FIFO: ida (cliente → servidor) e volta separadas, jitter
  uniforme com seed e interrupção opcional.
- A ordem do fluxo é preservada.
- É **atraso de aplicação** sobre TCP em loopback, não prova de comportamento
  sob perda.
- Só é carregado por `--test-net-profile` num binário de desenvolvimento não
  exportado; `tests/` fica fora da exportação Windows.
