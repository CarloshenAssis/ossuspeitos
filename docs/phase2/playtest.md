# Playtest humano — Fase 2

Use a branch `codex/gameplay-specs-09-16` com **Godot4.4.1**. Protocolo12: clientes e servidor precisam da mesma revisão; builds11 são recusadas. A branch contém o histórico doPR31 ainda aberto, não depende de assumir que main já o recebeu. Não usar o endpoint público atual para certificar essa branch antes de um deploy autorizado.

## Execução local

No desktop com display/áudio, importe o projeto e abra o menu:

```sh
godot --path . --import
godot --path . -- --mode=menu
```

Menu → Criar partida local; em outras instâncias, use nomes distintos e Entre em `127.0.0.1`, porta9080 (ou a porta escolhida no menu). São necessários quatro jogadores para começar; capacidade oito. Para servidor de desenvolvimento explícito:

```sh
godot --headless --path . -- --mode=server --bind=127.0.0.1 --port=9080
# Em outro processo, gráfico:
godot --path . -- --mode=client --client-id=Pessoa1 --url=ws://127.0.0.1:9080
```

Cloud atual dispõe apenas de displayX11/Mesa por software para automação, não desktop remoto humano certificado. Seu binário fixado pode ser usado com `source /workspace/.ossuspeitos-state/mission-sdd/env.sh` e `"$GODOT_BIN"` no lugar de godot. Não use o godot4.6.3 que também existe noPATH deste host.

## Controles e observações

- WASD/mouse: movimento/mira existentes, sem sprint/jump novos.
- E: coletar arma/munição próxima; na ausência de pickup, abrir/fechar porta próxima.
- F: pegar objeto leve; G: empurrar; Q: soltar. Objeto da cozinha é pesado, só empurrável. Alcance2.5m; não atravessa parede/porta, nem pode fechar sobre jogador/prop.
- I: inspecionar corpo próximo; retorno privado identifica rótulo público e eliminação da rodada. Não revela papel, autor ou arma.
- Mouse esquerdo/R: disparo/recarga existentes. Dano, vida, munição e vitória continuam oficiais no servidor.
- Esc libera mouse; F10 sai. Eliminado usa Q/E para espectador conforme controles existentes.

Configurações → Volumes da partida: passos, portas/objetos e combate independentes; volume geral permaneceMaster. Reduzir movimento cancela efeitos visuais transitórios/corpo. Perfis baixo/padrão/alto existentes permanecem; baixo é alternativa útil em software. Oclusão sonora por AABB está experimental/desligada por padrão; não há voz nem trilha contínua nova.

## Roteiro de avaliação

1. Quatro pessoas entram; compare portas e objetos vistos em dois clientes.
2. Uma fecha a porta do escritório; outra tenta cruzar e atirar através dela. Reabra e repita. Registre qualquer desacordo entre malha, movimento e tiro.
3. Duas tentam pegar o mesmo objeto; confirme único dono. Transporte, solte, observe queda/som e empurre. Tente fechar porta com objeto/jogador no vão.
4. Caminhe em diferentes distâncias e ambientes; ajuste categorias/zero. Confira posição percebida, ausência de duplicação e se pistas são legíveis sem cobrir disparos.
5. Observe remoto parado/andando, disparando, recarregando e interagindo. Verifique interrupção por morte e conforto com reduzir movimento.
6. Após eliminação enquanto rodada segue, dois vivos inspecionam o corpo. Só solicitantes recebem texto; morto/distante não obtém nova inspeção.
7. Termine a rodada pelos combates normais; confira restauração de portas/props/corpos/inspeções e repita com oito pessoas.
8. Saia/reconecte conforme regras da sala. No online, reentrada em rodada ativa permanece bloqueada pela regra anterior; confira lobby/contagem e isolamento entre salas.

Registre revisão, plataforma/GPU/driver/dispositivo de áudio, número de clientes, latência real, perfil gráfico, reprodução e logs. Capture desconforto, visibilidade, falsa associação de som, clipping ou divergência. Testes automatizados não substituem essa avaliação; Android/macOS/GPUfísica não certificados.

## Automação reproduzível

```sh
source /workspace/.ossuspeitos-state/mission-sdd/env.sh
python3 tests/run_phase2_unit_tests.py --logs /tmp/suspeitos-phase2-units
PHASE2_CLIENTS=4 PROFILE=local TEST_LOG_DIR=/tmp/suspeitos-phase2-four bash tests/phase2_network_test.sh
PHASE2_CLIENTS=4 PROFILE=rtt200 TEST_LOG_DIR=/tmp/suspeitos-phase2-delay bash tests/phase2_network_test.sh
PHASE2_CLIENTS=8 PHASE2_ROUNDS=3 PROFILE=local TEST_LOG_DIR=/tmp/suspeitos-phase2-eight bash tests/phase2_network_test.sh
bash tests/phase2_network_wrapper_test.sh
bash tests/physics_backend_lab_test.sh
```

RTT200 injeta100ms por direção na aplicação sobre WebSocket/TCP local; não simula perda física. O laboratório compara backends isolados sem alterar o backend de produção. ExportsWindows/Web e container são artifacts deCI, não publicaçãoPages/Railway; verificar resultados doPR antes de baixar/usar.
