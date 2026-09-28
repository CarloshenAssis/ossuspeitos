class_name PlayerMessages
extends RefCounted

## Fase 10: mensagens de conexão para o jogador, em português simples e sempre
## com o que fazer. Nunca levam endereço, IP, porta, versão de protocolo, nome
## de RPC ou de classe: esses detalhes vão só para o log de depuração.
## Os erros de sala ficam em `RoomRules.ERRORS` (mesma regra).

## Motivo da volta ao menu -> texto. `online` = servidor online (Railway);
## senão, partida local/LAN digitada pelo jogador.
static func connection(reason: String, online: bool, shutdown_agreed: bool = false) -> String:
	match reason:
		"timeout":
			return "O servidor demorou demais para responder. Confira sua internet e tente de novo." if online \
				else "O servidor não respondeu a tempo. Confira endereço e porta e se a partida foi criada."
		"connection_failed":
			return "Servidor indisponível no momento. Tente de novo em alguns minutos." if online \
				else "Não foi possível conectar. Confira endereço e porta e se a partida foi criada."
		"server_disconnected":
			if shutdown_agreed:
				return "O servidor encerrou a partida. Entre de novo quando ele voltar."
			return "A conexão caiu. Entre de novo na sala pelo código (se a rodada estiver em andamento, espere ela acabar)." if online \
				else "Conexão com o servidor perdida. Confira com o anfitrião se a partida continua aberta e conecte de novo."
	return "Algo deu errado na conexão. Tente de novo."

## Recusa na entrada (handshake) -> texto.
static func join_rejected(reason: String) -> String:
	match reason:
		"protocol_version":
			return "Versão incompatível do jogo. Atualize a página (ou baixe a versão mais recente): todos precisam da mesma versão."
		"room_unavailable":
			return "A sala está cheia (8 jogadores). Tente mais tarde ou crie outra partida."
		"server_full":
			return "O servidor está lotado no momento. Tente de novo em alguns minutos."
		"name_taken":
			return "Já existe alguém com esse nome. Escolha outro nome."
		"invalid_client":
			return "Nome recusado. Use até 20 letras, números, espaço, - ou _."
	return "Entrada recusada pelo servidor. Tente de novo."
