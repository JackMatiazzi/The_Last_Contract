class_name VictoryEpilogue
extends AdventurerCutscene
## Epílogo da vitória: o grupo volta à vila e o Lorde cobra o contrato do jeito dele. Neste mundo contrato
## tem peso e sempre se cumpre, inclusive as letras miúdas: quem venceu os mortos vira a próxima leva.

const LINES: Array[String] = [
	"Contrato cumprido.",
	"%s... Vocês cumpriram algo que eu não achava possível.",
	"Mas não se preocupem.\nLogo estarão lá de novo, como uma nova leva.",
	"Neste reino, todo contrato é cumprido.",
]


## chamada pela linha do tempo; a fala do Lorde leva os nomes de quem assinou
func say(index: int) -> void:
	var line := LINES[index]
	(get_node("UI/Caption") as Label).text = line % signatures() if line.contains("%s") else line


static func signatures() -> String:
	var peers: Array = Net.peers_in_order() if Net.is_online() else [Engine.get_main_loop().get_multiplayer().get_unique_id()]
	return VictoryScreen.join_names(peers.map(func(peer_id: int) -> String: return Net.display_name(peer_id)))
