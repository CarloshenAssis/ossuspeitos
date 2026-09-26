class_name MenuSettings
extends RefCounted

## Preferências locais do jogador (fase 7), em `user://settings.cfg`.
## Guarda só o que é útil e não sensível: último nome válido, volume,
## sensibilidade do mouse, modo de tela, resolução e "reduzir movimento".
## Endereço, porta e URL online não são salvos.

const PATH := "user://settings.cfg"
const SECTION := "preferences"

const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
const VOLUME_DEFAULT := 0.8
## Multiplicador da sensibilidade base do jogo; nunca zero nem absurda.
const SENSITIVITY_MIN := 0.25
const SENSITIVITY_MAX := 3.0
const SENSITIVITY_DEFAULT := 1.0
const RESOLUTIONS := [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

## Caminho alternativo só para testes (arquivo isolado).
static var path_override := ""
## Tela salva já aplicada neste processo (a volta ao menu recarrega a cena e
## não deve redimensionar a janela de novo).
static var display_applied := false

var player_name := ""
var volume := VOLUME_DEFAULT
var sensitivity := SENSITIVITY_DEFAULT
var fullscreen := false
var resolution := Vector2i(960, 540)
var reduce_motion := false
## O arquivo tinha preferência de tela (senão, a janela fica como o projeto abre).
var display_saved := false

static func file_path() -> String:
	return path_override if not path_override.is_empty() else PATH

static func load_saved() -> MenuSettings:
	var settings := MenuSettings.new()
	var file := ConfigFile.new()
	if file.load(file_path()) != OK:
		return settings
	settings.player_name = str(file.get_value(SECTION, "player_name", ""))
	if not RoundRules.label_problem(settings.player_name).is_empty():
		settings.player_name = ""
	settings.volume = clampf(float(file.get_value(SECTION, "volume", VOLUME_DEFAULT)), VOLUME_MIN, VOLUME_MAX)
	settings.sensitivity = clamp_sensitivity(float(file.get_value(SECTION, "sensitivity", SENSITIVITY_DEFAULT)))
	settings.fullscreen = bool(file.get_value(SECTION, "fullscreen", false))
	var saved: Variant = file.get_value(SECTION, "resolution", Vector2i(960, 540))
	settings.resolution = saved if typeof(saved) == TYPE_VECTOR2I and saved in RESOLUTIONS else Vector2i(960, 540)
	settings.display_saved = file.has_section_key(SECTION, "resolution") or file.has_section_key(SECTION, "fullscreen")
	settings.reduce_motion = bool(file.get_value(SECTION, "reduce_motion", false))
	return settings

func save() -> int:
	var file := ConfigFile.new()
	file.set_value(SECTION, "player_name", player_name if RoundRules.label_problem(player_name).is_empty() else "")
	file.set_value(SECTION, "volume", clampf(volume, VOLUME_MIN, VOLUME_MAX))
	file.set_value(SECTION, "sensitivity", clamp_sensitivity(sensitivity))
	file.set_value(SECTION, "fullscreen", fullscreen)
	file.set_value(SECTION, "resolution", resolution)
	file.set_value(SECTION, "reduce_motion", reduce_motion)
	return file.save(file_path())

static func clamp_sensitivity(value: float) -> float:
	if not is_finite(value):
		return SENSITIVITY_DEFAULT
	return clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)

## Volume geral no barramento Master (vale para o jogo inteiro, menu e partida).
func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if volume <= 0.001:
		AudioServer.set_bus_mute(bus, true)
	else:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, linear_to_db(volume))

## Modo de tela e resolução, só onde a plataforma permite (não na Web nem no
## headless). Resolução vale para a janela; em tela cheia usa a do monitor.
func apply_display() -> void:
	if not supports_display_settings():
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)

## Na abertura do jogo: aplica a tela salva uma vez por processo.
func apply_saved_display_once() -> void:
	if display_applied or not display_saved:
		return
	display_applied = true
	apply_display()

static func supports_display_settings() -> bool:
	return not OS.has_feature("web") and DisplayServer.get_name() != "headless"

static func supports_quit() -> bool:
	return not OS.has_feature("web")

## Criar partida local (processo de servidor) e entrar por LAN (`ws://` a
## partir de uma página `https`) não existem no navegador: a build Web só
## joga online.
static func supports_local_play() -> bool:
	return not OS.has_feature("web")
