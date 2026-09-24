class_name OnlineEndpoint
extends RefCounted

## Endereço do servidor online (futuro Railway), num único lugar (fase 7).
## Nenhuma tela conhece a URL: o menu pergunta aqui.
##
## Prioridade, da mais forte para a mais fraca:
##   1. argumento `--online-url=...` (desenvolvimento e testes);
##   2. variável de ambiente `ARMED_MYSTERY_ONLINE_URL` (desktop; não existe na Web);
##   3. ProjectSettings `armed_mystery/network/online_url`. Vazio em
##      `project.godot`; uma build exportada pode definir o valor sem
##      recompilar com um `override.cfg` ao lado do executável:
##        [armed_mystery]
##        network/online_url="wss://SEU-SERVICO.up.railway.app"
## Nada configurado: o modo online aparece como "ainda não configurado".
## O valor `off` (argumento ou variável) desliga o online nesta execução, mesmo
## com endereço no projeto: testes e eventos só na LAN.
##
## Só o endereço público do servidor: nunca token, senha ou segredo. URL com
## credencial (`usuario@`) ou consulta (`?`) é recusada.

const SETTING := "armed_mystery/network/online_url"
const ENV_VAR := "ARMED_MYSTERY_ONLINE_URL"
const ARGUMENT := "online-url"
const DISABLED := "off"

## {url, source} da primeira fonte não vazia; url vazia se nenhuma.
static func configured(arguments: Dictionary) -> Dictionary:
	var from_argument := str(arguments.get(ARGUMENT, "")).strip_edges()
	if from_argument == DISABLED:
		return {"url": "", "source": "disabled"}
	if not from_argument.is_empty():
		return {"url": from_argument, "source": "argument"}
	if not OS.has_feature("web"):
		var from_env := OS.get_environment(ENV_VAR).strip_edges()
		if from_env == DISABLED:
			return {"url": "", "source": "disabled"}
		if not from_env.is_empty():
			return {"url": from_env, "source": "environment"}
	var from_setting := str(ProjectSettings.get_setting(SETTING, "")).strip_edges()
	if not from_setting.is_empty():
		return {"url": from_setting, "source": "project_settings"}
	return {"url": "", "source": "none"}

## Valida uma URL de servidor. Devolve {ok, reason, url, host, secure}.
## `production` (build exportada) exige `wss://`, exceto para endereço de
## loopback ou de rede local (teste de LAN).
static func validate(raw_url: String, production: bool) -> Dictionary:
	var url := raw_url.strip_edges()
	var result := {"ok": false, "reason": "", "url": url, "host": "", "secure": false}
	if url.is_empty():
		result["reason"] = "not_configured"
		return result
	var scheme := ""
	if url.begins_with("wss://"): scheme = "wss"
	elif url.begins_with("ws://"): scheme = "ws"
	else:
		result["reason"] = "scheme"
		return result
	var rest := url.substr(scheme.length() + 3)
	if rest.contains("@") or rest.contains("?") or rest.contains("#") or rest.contains(" "):
		result["reason"] = "forbidden_part"
		return result
	var authority := rest.get_slice("/", 0)
	var host := authority
	if authority.contains(":"):
		host = authority.get_slice(":", 0)
		var port_text := authority.get_slice(":", 1)
		if not port_text.is_valid_int() or port_text.to_int() < 1 or port_text.to_int() > 65535:
			result["reason"] = "port"
			return result
	if host.is_empty() or host.length() > 253 or not DesktopSession.validate_address(host).is_empty():
		result["reason"] = "host"
		return result
	result["host"] = host
	result["secure"] = scheme == "wss"
	if production and scheme == "ws" and not is_local_host(host):
		result["reason"] = "insecure"
		return result
	result["ok"] = true
	return result

static func is_local_host(host: String) -> bool:
	if host == "localhost" or host.begins_with("127."):
		return true
	var parts := host.split(".")
	if parts.size() != 4 or not DesktopSession._is_ipv4(host):
		return false
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	return a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)

## Estado para o menu: configurado e válido, ou o motivo em português.
static func resolve(arguments: Dictionary) -> Dictionary:
	var source := configured(arguments)
	var production := OS.has_feature("template") and not OS.is_debug_build()
	var check := validate(str(source["url"]), production)
	if source["source"] == "disabled":
		check["reason"] = "disabled"
	check["source"] = source["source"]
	check["message"] = message_for(str(check["reason"]))
	return check

static func message_for(reason: String) -> String:
	match reason:
		"": return ""
		"not_configured": return "Servidor online ainda não configurado. Use \"Criar partida local\" ou \"Entrar em partida LAN\"."
		"disabled": return "Modo online desligado nesta execução. Use \"Criar partida local\" ou \"Entrar em partida LAN\"."
		"insecure": return "O servidor online configurado não usa conexão segura (wss://). Conexão bloqueada."
	return "O endereço do servidor online configurado é inválido. Avise quem publicou esta versão."
