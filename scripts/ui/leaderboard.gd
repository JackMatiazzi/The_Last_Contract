class_name Leaderboard
## Lê o placar da API em linhas prontas para a tela. Nomes de grupo e apelidos foram digitados por
## outros jogadores: passam pela mesma limpeza do lobby e só viram texto puro.

const GROUPS_PATH := "/placar/grupos"
const SOLO_PATH := "/placar/solo"
const CLASSES: Array[String] = ["Knight", "Barbarian", "Mage", "Rogue"]
const MISSING := "—"


## [posição, grupo, jogadores, tentativas, tempo] por partida; null se a resposta não for um placar
static func parse_groups(text: String) -> Variant:
	var data: Variant = JSON.parse_string(text)
	if not data is Array:
		return null
	var rows: Array = []
	for entry: Variant in data:
		if not entry is Dictionary:
			continue
		var names: Array = []
		for player: Variant in entry.get("jogadores", []):
			if player is Dictionary:
				names.append(Net.clean_name(str(player.get("apelido", ""))))
		rows.append([str(rows.size() + 1), Net.clean_text(str(entry.get("rotulo", "")), Net.MAX_GROUP_NAME_LENGTH),
			", ".join(names), _whole(entry.get("tentativas")), _minutes(entry.get("minutos"))])
	return rows


## [classe, partidas, vitórias, melhor tempo, média de tentativas], sempre as quatro classes na mesma ordem
static func parse_solo(text: String) -> Variant:
	var data: Variant = JSON.parse_string(text)
	if not data is Array:
		return null
	var by_class := {}
	for entry: Variant in data:
		if entry is Dictionary:
			by_class[str(entry.get("classe", ""))] = entry
	var rows: Array = []
	for adventurer in CLASSES:
		var entry: Dictionary = by_class.get(adventurer, {})
		rows.append([adventurer, _whole(entry.get("partidas", 0)), _whole(entry.get("vitorias", 0)),
			_minutes(entry.get("melhor_minutos")), _decimal(entry.get("media_tentativas"))])
	return rows


static func _whole(value: Variant) -> String:
	return str(int(value)) if value is float or value is int else MISSING


static func _decimal(value: Variant) -> String:
	return ("%.1f" % value).replace(".", ",") if value is float or value is int else MISSING


static func _minutes(value: Variant) -> String:
	return _decimal(value) + " min" if value is float or value is int else MISSING
