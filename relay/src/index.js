import { apagarApelido, diaUtc, limpezaDiaria, placar, registrarTelemetria, usoDoDia } from "./banco.js";
import { codigoValido } from "./protocolo.js";
import { Registro } from "./registro.js";
import { BYTES_DO_CORPO, chaveDoApelido, validarRelatorio } from "./relatorio.js";
import { recusarConexao, Sala } from "./sala.js";

export { Registro, Sala };

// sobe junto com o formato das mensagens: jogo e sala de versoes diferentes nao conversam
const VERSAO = "1";
const RETENCAO_DIAS = 90;
// o Cache API nao funciona em *.workers.dev; o placar fica na memoria do Worker por 5 minutos
const PLACAR_CACHE_S = 300;
let placarGuardado = { ate: 0, dados: null };

// GET    /salas             (WebSocket) cria uma sala e entra como host
// GET    /salas/CODIGO      (WebSocket) entra na sala como cliente, com ?id= proposto pelo jogo
// POST   /telemetria        relatorio do fim da partida, com a ficha que a sala deu ao jogador
// GET    /placar            os 20 melhores apelidos (vitorias, melhor tentativa, partidas)
// GET    /uso               requisicoes e partidas de hoje (exige o ADMIN_TOKEN)
// DELETE /jogadores/APELIDO apaga o que o apelido gerou (pedido LGPD); exige o ADMIN_TOKEN
// GET    /saude             responde ok, para conferir o deploy
export default {
	async fetch(request, env) {
		const url = new URL(request.url);
		const partes = url.pathname.split("/").filter(Boolean);
		const rota = `${request.method} /${partes[0] ?? ""}`;
		switch (rota) {
			case "GET /saude":
				return new Response("ok");
			case "GET /salas":
				return conectar(request, env, url, partes);
			case "POST /telemetria":
				return receberTelemetria(request, env);
			case "GET /placar":
				return json(await placarComCache(env));
			case "GET /uso":
				return (await administrador(request, env)) ? json(await usoDoDia(env.DB, diaUtc(Date.now()))) : proibido();
			case "DELETE /jogadores":
				return apagarJogador(request, env, partes);
			default:
				return new Response("nao encontrado", { status: 404 });
		}
	},

	// uma vez por dia: o que passou da retencao sai do banco (LGPD) e o placar e recontado
	async scheduled(_evento, env) {
		await limpezaDiaria(env.DB, Date.now(), limite(env.RETENCAO_DIAS, RETENCAO_DIAS));
		placarGuardado = { ate: 0, dados: null };
	},
};

async function conectar(request, env, url, partes) {
	if (partes.length > 2) {
		return new Response("nao encontrado", { status: 404 });
	}
	if (request.headers.get("Upgrade") !== "websocket") {
		return new Response("use WebSocket", { status: 426 });
	}
	// o jogo nao manda Origin; navegador manda, e uma pagina qualquer usaria o relay com o IP do visitante
	if (request.headers.has("Origin")) {
		return proibido();
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
}

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
	return paraSala(request, env, { sala: codigo, papel: "cliente", id });
}

async function criarSala(request, env) {
	const reserva = await registro(env).reservar(ipDe(request));
	if (reserva.erro) {
		return recusarConexao(reserva.erro);
	}
	return paraSala(request, env, { sala: reserva.codigo, papel: "host", partida: reserva.partida });
}

function paraSala(request, env, parametros) {
	const destino = new URL("https://sala/conectar");
	for (const [nome, valor] of Object.entries(parametros)) {
		destino.searchParams.set(nome, valor);
	}
	return env.SALA.get(env.SALA.idFromName(parametros.sala)).fetch(new Request(destino, request));
}

async function receberTelemetria(request, env) {
	if (request.headers.has("Origin")) {
		return proibido();
	}
	if (Number(request.headers.get("Content-Length") ?? 0) > BYTES_DO_CORPO) {
		return json({ erro: "relatorio grande demais" }, 413);
	}
	if (!(await registro(env).podeRelatar(ipDe(request)))) {
		return json({ erro: "relatorios demais, espere um minuto" }, 429);
	}
	const texto = await request.text();
	if (new TextEncoder().encode(texto).length > BYTES_DO_CORPO) {
		return json({ erro: "relatorio grande demais" }, 413);
	}
	const { relatorio, erro } = validarRelatorio(lerJson(texto));
	if (erro) {
		return json({ erro }, 400);
	}
	return gravarTelemetria(env, relatorio);
}

// regra do banco que escapou da validacao vira 400, nao 500; banco fora do ar vira 503
async function gravarTelemetria(env, relatorio) {
	try {
		if (!(await registrarTelemetria(env.DB, relatorio, Date.now()))) {
			return json({ erro: "ficha invalida ou ja usada" }, 409);
		}
		return json({ ok: true });
	} catch (erro) {
		const regra = String(erro).includes("CHECK constraint");
		console.error(JSON.stringify({ evento: regra ? "telemetria-recusada" : "banco-indisponivel", etapa: "telemetria", erro: String(erro) }));
		return json({ erro: regra ? "relatorio invalido" : "banco indisponivel" }, regra ? 400 : 503);
	}
}

async function placarComCache(env) {
	const segundos = Number(env.PLACAR_CACHE_S ?? PLACAR_CACHE_S);
	if (segundos > 0 && placarGuardado.ate > Date.now()) {
		return placarGuardado.dados;
	}
	const dados = await placar(env.DB);
	placarGuardado = { ate: Date.now() + segundos * 1000, dados };
	return dados;
}

async function apagarJogador(request, env, partes) {
	if (!(await administrador(request, env))) {
		return proibido();
	}
	const chave = chaveDoApelido(lerUri(partes[1] ?? ""));
	if (!chave) {
		return json({ erro: "informe o apelido" }, 400);
	}
	placarGuardado = { ate: 0, dados: null };
	return json({ apagados: await apagarApelido(env.DB, chave) });
}

async function administrador(request, env) {
	return tokenConfere(env.ADMIN_TOKEN, request.headers.get("Authorization") ?? "");
}

function proibido() {
	return new Response("proibido", { status: 403, headers: { "X-Content-Type-Options": "nosniff" } });
}

function lerUri(texto) {
	try {
		return decodeURIComponent(texto);
	} catch {
		return "";
	}
}

// sem ADMIN_TOKEN configurado (wrangler secret put ADMIN_TOKEN) a rota fica fechada.
// Compara os hashes em tempo constante: o tempo da resposta nao entrega o token aos poucos
async function tokenConfere(token, cabecalho) {
	if (!token) {
		return false;
	}
	const [esperado, recebido] = await Promise.all([`Bearer ${token}`, cabecalho].map((texto) => crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto))));
	return crypto.subtle.timingSafeEqual(esperado, recebido);
}

function json(dados, status = 200) {
	return new Response(JSON.stringify(dados), { status, headers: { "Content-Type": "application/json; charset=utf-8", "X-Content-Type-Options": "nosniff" } });
}

function lerJson(texto) {
	try {
		return JSON.parse(texto);
	} catch {
		return null;
	}
}

function limite(valor, padrao) {
	const numero = Number(valor);
	return Number.isInteger(numero) && numero > 0 ? numero : padrao;
}
