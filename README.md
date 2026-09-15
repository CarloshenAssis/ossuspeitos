# Armed Mystery

Protótipo Godot 4 com servidor headless autoritativo e clientes locais conectados
por WebSocket. O segundo marco adiciona uma arena 3D provisória, movimento em
primeira pessoa e cápsulas interpoladas para os jogadores remotos.

## Requisitos

- Godot 4.4 ou mais recente (`godot4` ou `godot` no `PATH`).
- Bash para executar o teste de integração.

## Execução local

Inicie o servidor (por padrão, somente em `127.0.0.1:9080`):

```bash
godot4 --headless --path . -- --mode=server
```

Em quatro terminais, varie o identificador do cliente:

```bash
godot4 --headless --path . -- --mode=client --client-id=client-1
```

O endereço pode ser alterado com `--url=ws://host:porta`. O servidor aceita
`--bind=endereço`, `--port=porta` e também a variável de ambiente `PORT`.
Nos clientes gráficos, use WASD para mover e o mouse para girar a câmera. O
cliente envia apenas eixos de entrada e variação de rotação; posição e velocidade
são calculadas, limitadas e publicadas pelo servidor.

## Teste servidor + quatro clientes

```bash
./tests/network_smoke_test.sh
```

O teste abre uma porta local aleatória, inicia cinco processos headless, exige
quatro sessões simultâneas com IDs de peer distintos e encerra todos os processos.
Se o executável não estiver no `PATH`, use
`GODOT_BIN=/caminho/para/godot ./tests/network_smoke_test.sh`.

Armas, papéis, lojas, Android e deploy do Railway não fazem parte deste marco.
