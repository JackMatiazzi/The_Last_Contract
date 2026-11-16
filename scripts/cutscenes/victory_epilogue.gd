class_name VictoryEpilogue
extends AdventurerCutscene
## Epílogo da vitória, no mesmo palco da derrota: a vila celebra o grupo, o Lorde manda prender, os guardas
## arrastam o herói ao cadafalso e o carrasco cumpre a sua parte.

const LINES: Array[String] = [
	"Contrato cumprido.",
	"A vila celebra quem a libertou.",
	"%s... Vocês cumpriram algo que eu não achava possível.",
	"Guardas, levem-nos.",
	"O contrato foi cumprido.\nNão fique sem ler. E, mesmo se ler, tenha certeza da índole do seu contratante.",
]


## chamada pela linha do tempo; a fala do Lorde leva os nomes de quem assinou
func say(index: int) -> void:
	var line := LINES[index]
	(get_node("UI/Caption") as Label).text = line % signatures() if line.contains("%s") else line


static func signatures() -> String:
	var peers: Array = Net.peers_in_order() if Net.is_online() else [Engine.get_main_loop().get_multiplayer().get_unique_id()]
	return VictoryScreen.join_names(peers.map(func(peer_id: int) -> String: return Net.display_name(peer_id)))
