class_name CharacterAppearance
extends RefCounted

## Aparência cosmética pública dos jogadores: um dos oito personagens em
## `res://assets/characters/`. É só visual e independente de papel, equipe,
## inventário ou qualquer estado privado: o servidor atribui na entrada da
## sessão (antes de existir papel) e publica no roster.
##
## `IDS` é a allowlist: qualquer valor fora dela vira `FALLBACK` no cliente.
## A ordem é a do pacote de personagens e define a ordem de atribuição.

const IDS: Array[String] = ["ember", "moss", "dawn", "night", "cedar", "ash", "sand", "plum"]
const FALLBACK := "ember"
const SCENE_PATH := "res://assets/characters/mystery_character_%s.glb"

static func is_valid(appearance_id: Variant) -> bool:
	return typeof(appearance_id) == TYPE_STRING and IDS.has(appearance_id)

static func sanitize(appearance_id: Variant) -> String:
	return str(appearance_id) if is_valid(appearance_id) else FALLBACK

static func scene_path(appearance_id: Variant) -> String:
	return SCENE_PATH % sanitize(appearance_id)

## Primeira aparência ainda não usada pelas sessões conectadas. Com até oito
## sessões, cada uma recebe uma variante distinta; depois disso (não ocorre com
## MAX_PLAYERS = 8) repete pela ordem.
static func first_free(used: Array) -> String:
	for appearance_id in IDS:
		if not used.has(appearance_id):
			return appearance_id
	return IDS[used.size() % IDS.size()]
