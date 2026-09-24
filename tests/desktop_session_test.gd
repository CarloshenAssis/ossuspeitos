extends SceneTree

## Testes determinísticos do menu de teste local: validação de nome, endereço e
## porta, detecção de porta ocupada, textos mostrados ao jogador e a garantia de
## que o menu não cria nenhuma autoridade de jogo.

var failures := 0
var checks := 0
var _menu: DesktopMenu
var _finished := false
var _emitted: Array = []

func _initialize() -> void:
	_test_names()
	_test_addresses()
	_test_ports()
	_test_urls_and_texts()
	_test_port_in_use_is_detected()
	_test_stop_is_idempotent_without_server()
	_menu = DesktopMenu.new()
	root.add_child(_menu)

func _process(_delta: float) -> bool:
	if _finished:
		return false
	_finished = true
	_test_menu_emits_only_valid_requests()
	if failures > 0:
		push_error("DESKTOP_SESSION_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return false
	print("DESKTOP_SESSION_TEST_OK checks=%d" % checks)
	quit(0)
	return false

func _test_names() -> void:
	_expect(DesktopSession.validate_name("jogador-0042").is_empty(), "default-style name is valid")
	_expect(DesktopSession.validate_name(DesktopSession.default_player_name()).is_empty(), "generated default name is valid")
	_expect(DesktopSession.validate_name("Ana_2").is_empty(), "letters, digits and underscore are valid")
	# Fase 7: letras do português, espaço, hífen e sublinhado.
	for good in ["com espaço", "ação", "João Ninguém", "  Ana  ", "Çé_2-x"]:
		_expect(DesktopSession.validate_name(good).is_empty(), "name '%s' is valid" % good)
	for bad in ["", "   ", "a".repeat(RoundRules.MAX_LABEL_LENGTH + 1), "x;rm", "<b>", "a\nb", "a\tb", "duas  vezes", "emoji 😀"]:
		_expect(not DesktopSession.validate_name(bad).is_empty(), "name '%s' is rejected" % bad.c_escape())

func _test_addresses() -> void:
	for good in ["127.0.0.1", "192.168.0.10", "10.0.0.255", "localhost", "meu-pc", "meu-pc.lan"]:
		_expect(DesktopSession.validate_address(good).is_empty(), "address %s is valid" % good)
	for bad in ["", "999.1.1.1", "1.2.3", "1.2.3.4.5", "192.168.0.10:9080", "ws://127.0.0.1", "http://x", "-pc", "pc-", "a b", "::1", "1234", "192.168.0.-1"]:
		_expect(not DesktopSession.validate_address(bad).is_empty(), "address '%s' is rejected" % bad)

func _test_ports() -> void:
	_expect(DesktopSession.parse_port("9080") == 9080, "default port parses")
	_expect(DesktopSession.parse_port(" 65535 ") == 65535, "max port with spaces parses")
	for bad in ["", "abc", "80", "1023", "65536", "-1", "90.5", "9080x"]:
		_expect(DesktopSession.parse_port(bad) == -1, "port '%s' is rejected" % bad)

func _test_urls_and_texts() -> void:
	_expect(DesktopSession.url_for(" 192.168.0.10 ", 9080) == "ws://192.168.0.10:9080", "url uses the websocket scheme")
	for address in DesktopSession.lan_addresses():
		_expect(not str(address).begins_with("127.") and str(address).count(".") == 3, "LAN list has only non-loopback IPv4 (%s)" % address)
	for code in ["port_in_use", "already_hosting", "spawn_failed", "server_exited", "server_timeout", "unable_to_listen"]:
		var message := DesktopSession.error_message(code, 9080)
		_expect(not message.is_empty() and not message.contains("(%s)" % code), "error %s has a clear message" % code)
	_expect(DesktopSession.error_message("port_in_use", 9080).contains("Nenhuma sala foi criada"), "port in use never claims a room")
	_expect(DesktopSession.hosted_address_text().is_empty(), "no address text while not hosting")
	DesktopSession.hosted_port = 9080
	DesktopSession.hosted_lan = false
	_expect(DesktopSession.hosted_address_text().contains("127.0.0.1:9080"), "loopback host shows its address and port")
	DesktopSession.hosted_lan = true
	_expect(DesktopSession.hosted_address_text().contains("9080"), "LAN host shows the port")
	DesktopSession.hosted_port = 0
	DesktopSession.hosted_lan = false

func _test_port_in_use_is_detected() -> void:
	var blocker := TCPServer.new()
	var port := 0
	for candidate in range(41000, 41100):
		if blocker.listen(candidate, DesktopSession.LOOPBACK_ADDRESS) == OK:
			port = candidate
			break
	_expect(port > 0, "test could reserve a loopback port")
	_expect(not DesktopSession.port_available(port, false), "occupied loopback port is detected")
	_expect(DesktopSession.start_hosted_server(port, false) == "port_in_use", "hosting on an occupied port fails before spawning")
	_expect(DesktopSession.hosted_pid == 0 and not DesktopSession.is_hosting(), "no server process was started")
	blocker.stop()
	_expect(DesktopSession.port_available(port, false), "released port is available again")

func _test_stop_is_idempotent_without_server() -> void:
	DesktopSession.stop_hosted_server("test")
	DesktopSession.stop_hosted_server("test")
	_expect(DesktopSession.hosted_pid == 0 and DesktopSession.hosted_status_path.is_empty(), "stopping twice without a server is harmless")

func _test_menu_emits_only_valid_requests() -> void:
	_menu.host_requested.connect(func(n, p, l, _a): _emitted.append(["host", n, p, l]))
	_menu.join_requested.connect(func(n, a, p, _t): _emitted.append(["join", n, a, p]))
	_menu.fill("ana", "9080", false, "999.1.1.1", "9080")
	_menu._submit_join()
	_expect(_emitted.is_empty(), "invalid address never reaches the network layer")
	_menu.fill("ana", "80", false, "127.0.0.1", "80")
	_menu._submit_host()
	_menu._submit_join()
	_expect(_emitted.is_empty(), "invalid port never reaches the network layer")
	_menu.fill("com\ttab", "9080", false, "127.0.0.1", "9080")
	_menu._submit_host()
	_expect(_emitted.is_empty(), "invalid name never reaches the network layer")
	_menu.fill("ana", "9090", true, "192.168.0.10", "9090")
	_menu._submit_host()
	# A tentativa do anfitrião termina (falha recuperável) antes da próxima.
	_menu.fail("teste", _menu.flow.attempt)
	_menu._submit_join()
	_expect(_emitted.size() == 2, "valid host and join requests are emitted")
	_expect(_emitted[0] == ["host", "ana", 9090, true], "host request carries name, port and explicit LAN choice")
	_expect(_emitted.size() == 2 and _emitted[1] == ["join", "ana", "192.168.0.10", 9090], "join request carries name, address and port")
	_menu.fill("ana", "9080", false, "", "")
	_expect(not _menu.lan_check.button_pressed, "LAN stays off unless chosen")
	# O menu não cria nenhuma autoridade: só nós de interface (e o som do menu).
	for node in _menu.find_children("*", "", true, false):
		_expect(node is Control or node is AudioStreamPlayer, "menu node %s is presentation only" % node.name)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("DESKTOP_SESSION_CHECK_FAILED %s" % message)
