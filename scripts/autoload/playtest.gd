extends Node
## registro de cada contrato para o playtest com os colegas: um .json por partida em user://playtest.
## so grava na build exportada ou com --playtest, para os testes e o editor nao encherem a pasta

const DIR := "user://playtest"

var enabled := OS.has_feature("template") or "--playtest" in OS.get_cmdline_user_args()
var directory := DIR
var last_path := ""
var _run := {}
var _started_msec := 0


func is_running() -> bool:
	return not _run.is_empty()


func start_run(adventurer: String, players: int, level: String) -> void:
	if not enabled:
		return
	_started_msec = Time.get_ticks_msec()
	var started_at := Time.get_datetime_string_from_system()
	# o peer separa as instancias de um co-op aberto na mesma maquina
	var file_name := "%s_%s_p%d_%03d.json" % [started_at.replace(":", "-"), adventurer.to_snake_case(), multiplayer.get_unique_id(), _started_msec % 1000]
	last_path = directory.path_join(file_name)
	_run = {
		"started_at": started_at,
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"adventurer": adventurer,
		"players": players,
		"level": level,
		"result": "",
		"events": [],
	}
	_save()


func record(kind: String, data := {}) -> void:
	if not is_running():
		return
	var event := data.merged({"type": kind, "t": elapsed(), "attempt": RunState.attempt})
	_run["events"].append(event)
	_save()


## fecha o arquivo: o proximo contrato abre outro
func finish(result: String) -> void:
	if not is_running():
		return
	record(result)
	_run["result"] = result
	_run["duration"] = elapsed()
	_save()
	_run = {}


func elapsed() -> float:
	return snappedf((Time.get_ticks_msec() - _started_msec) / 1000.0, 0.1)


static func position_of(node: Node3D) -> Array:
	return [snappedf(node.global_position.x, 0.1), snappedf(node.global_position.y, 0.1), snappedf(node.global_position.z, 0.1)]


# grava a cada evento: se o jogo fechar no meio, o que aconteceu ate ali fica salvo
func _save() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(last_path, FileAccess.WRITE)
	if file == null:
		push_warning("Playtest: nao deu para gravar %s (%s)" % [last_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(_run, "\t"))
