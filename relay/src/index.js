import { codigoValido } from "./protocolo.js";
import { Registro } from "./registro.js";
import { recusarConexao, Sala } from "./sala.js";

export { Registro, Sala };

// sobe junto com o formato das mensagens: jogo e sala de versoes diferentes nao conversam
const VERSAO = "1";

// GET /salas          (WebSocket) cria uma sala e entra como host
// GET /salas/CODIGO   (WebSocket) entra na sala como cliente, com ?id= proposto pelo jogo
// GET /saude          responde ok, para conferir o deploy
export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		if (url.pathname === "/saude") {
			return new Response("ok");
		}
		const partes = url.pathname.split("/").filter(Boolean);
		if (partes[0] !== "salas" || partes.length > 2) {
			return new Response("nao encontrado", { status: 404 });
		}
		if (request.headers.get("Upgrade") !== "websocket") {
			return new Response("use WebSocket", { status: 426 });
		}
		// o jogo nao manda Origin; navegador manda, e uma pagina qualquer usaria o relay com o IP do visitante
		if (request.headers.has("Origin")) {
			return new Response("proibido", { status: 403 });
		}
		if (url.searchParams.get("v") !== VERSAO) {
			return recusarConexao("A versão do jogo é diferente da sala. Atualize o jogo.");
		}
		if (partes.length === 1) {
			return criarSala(request, env);
		}
		const codigo = partes[1].toUpperCase();
		if (!codigoValido(codigo)) {
			return recusarConexao("Código de sala inválido.");
		}
		return entrarNaSala(request, env, codigo, url.searchParams.get("id") ?? "");
	},
};

function registro(env) {
	return env.REGISTRO.get(env.REGISTRO.idFromName("global"));
}

function ipDe(request) {
	return request.headers.get("CF-Connecting-IP") ?? "local";
}

// o registro confere o codigo e o limite de tentativas antes de acordar a sala
async function entrarNaSala(request, env, codigo, id) {
	const resposta = await registro(env).entrar(ipDe(request), codigo);
	if (resposta.erro) {
		return recusarConexao(resposta.erro);
	}
	return paraSala(request, env, codigo, "cliente", id);
}

async function criarSala(request, env) {
	const reserva = await registro(env).reservar(ipDe(request));
	if (reserva.erro) {
		return recusarConexao(reserva.erro);
	}
	return paraSala(request, env, reserva.codigo, "host", "");
}

function paraSala(request, env, codigo, papel, id) {
	const destino = new URL("https://sala/conectar");
	destino.searchParams.set("sala", codigo);
	destino.searchParams.set("papel", papel);
	destino.searchParams.set("id", id);
	return env.SALA.get(env.SALA.idFromName(codigo)).fetch(new Request(destino, request));
}
