import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { escreverRegistros } from "../src/protocolo.js";
import { derrubar, subirRelay } from "./local.js";

// banco D1 local: consumo das partidas, orcamento do dia, fichas, telemetria, placar, apagamento e retencao
const PORTA = 8797;
const HTTP = `http://127.0.0.1:${PORTA}`;
const WS = `ws://127.0.0.1:${PORTA}`;
const ADMIN = "token-de-teste";
let wrangler;

// uma partida de 2020 ja no banco, para a limpeza diaria ter o que apagar
const PARTIDA_ANTIGA = [
	"INSERT INTO partidas (id, dia, inicio) VALUES ('antiga', '2020-01-01', 1577836800000)",
	"INSERT INTO telemetria (partida_id, apelido, apelido_chave, classe, resultado, tentativas, mortes, minutos, dados, criada) VALUES ('antiga', 'Veterano', 'veterano', 'Knight', 'victory', 1, 0, 40, '[]', 1577836800000)",
	"INSERT INTO placar (apelido_chave, apelido, partidas, vitorias, melhor_tentativa) VALUES ('veterano', 'Veterano', 1, 1, 1)",
];

before(async () => {
	wrangler = await subirRelay(PORTA, { ADMIN_TOKEN: ADMIN, PLACAR_CACHE_S: 0, ESTIMATIVA_SALA_ABERTA: 4000, ORCAMENTO_DIARIO: 6000, SALAS_ABERTAS_POR_IP: 100, SALAS_POR_IP_POR_MINUTO: 100, RELATORIOS_POR_IP_POR_MINUTO: 500 }, PARTIDA_ANTIGA);
});

after(() => derrubar(wrangler));

function conectar(url) {
	const ws = new WebSocket(url);
	ws.binaryType = "arraybuffer";
	const controles = [];
	ws.addEventListener("message", (evento) => typeof evento.data === "string" && controles.push(JSON.parse(evento.data)));
	return { ws, controles, primeiro: () => ate(() => controles[0]).then(() => controles[0]) };
}

async function ate(condicao, limite = 8000) {
	const fim = Date.now() + limite;
	while (!condicao()) {
		if (Date.now() > fim) {
			throw new Error("tempo esgotado");
		}
		await new Promise((resolver) => setTimeout(resolver, 25));
	}
}

async function partidaEncerrada() {
	const host = conectar(`${WS}/salas?v=1`);
	const boasVindas = await host.primeiro();
	const cliente = conectar(`${WS}/salas/${boasVindas.sala}?v=1&id=500`);
	const fichaCliente = (await cliente.primeiro()).ficha;
	host.ws.send(escreverRegistros([{ par: 0, canal: 0, modo: 2, dados: new Uint8Array([1, 2, 3]) }]));
	await new Promise((resolver) => setTimeout(resolver, 200));
	host.ws.send(JSON.stringify({ t: "encerrar" }));
	await ate(() => cliente.controles.some((controle) => controle.t === "encerrada"));
	return { fichaHost: boasVindas.ficha, fichaCliente };
}

function relatorio(ficha, extra = {}) {
	return { ficha, apelido: "Torvald", classe: "Barbarian", resultado: "victory", tentativas: 2, mortes: 3, minutos: 0.5, eventos: [{ type: "player_died", t: 300 }], ...extra };
}

async function enviar(corpo) {
	const resposta = await fetch(`${HTTP}/telemetria`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(corpo) });
	return resposta.status;
}

async function lerJson(caminho, opcoes) {
	return (await fetch(`${HTTP}${caminho}`, opcoes)).json();
}

test("cada jogador recebe uma ficha e a partida encerrada entra no consumo do dia", async () => {
	const { fichaHost, fichaCliente } = await partidaEncerrada();

	assert.match(fichaHost, /^[0-9a-f]{64}$/);
	assert.notEqual(fichaHost, fichaCliente);
	const admin = { headers: { Authorization: `Bearer ${ADMIN}` } };
	let uso = await lerJson("/uso", admin);
	for (let i = 0; i < 40 && uso.encerradas !== 1; i++) {
		await new Promise((resolver) => setTimeout(resolver, 100));
		uso = await lerJson("/uso", admin);
	}
	assert.equal(uso.encerradas, 1);
	assert.ok(uso.requisicoes >= 1);
});

test("relatorio com ficha valida entra uma vez so", async () => {
	const { fichaHost } = await partidaEncerrada();

	assert.equal(await enviar(relatorio(fichaHost)), 200);
	assert.equal(await enviar(relatorio(fichaHost)), 409);
	assert.equal(await enviar(relatorio("0".repeat(64))), 409);
});

test("a mesma ficha enviada duas vezes ao mesmo tempo entra uma vez so", async () => {
	const { fichaHost } = await partidaEncerrada();

	const respostas = await Promise.all([enviar(relatorio(fichaHost)), enviar(relatorio(fichaHost))]);

	assert.deepEqual(respostas.sort(), [200, 409]);
});

test("relatorio que nao bate com a partida nao entra no placar", async () => {
	const { fichaHost } = await partidaEncerrada();
	const sozinho = conectar(`${WS}/salas?v=1`);
	const fichaSozinho = (await sozinho.primeiro()).ficha;

	assert.equal(await enviar(relatorio(fichaHost, { minutos: 30 })), 409);
	assert.equal(await enviar(relatorio(fichaSozinho)), 409);
	assert.equal(await enviar(relatorio(fichaHost)), 200);
	sozinho.ws.close();
});

test("consumo do dia so com o token de administrador", async () => {
	assert.equal((await fetch(`${HTTP}/uso`)).status, 403);
});

test("relatorio fora das regras e recusado antes do banco", async () => {
	const { fichaHost } = await partidaEncerrada();

	assert.equal(await enviar(relatorio(fichaHost, { classe: "Dragao" })), 400);
	assert.equal(await enviar(relatorio(fichaHost, { tentativas: 0 })), 400);
	assert.equal(await enviar(relatorio(fichaHost, { apelido: "​‮" })), 400);
	assert.equal(await enviar(relatorio(fichaHost, { eventos: Array(700).fill({ type: "group_cleared" }) })), 400);
	assert.equal(await enviar(relatorio(fichaHost, { eventos: Array(4000).fill({ type: "group_cleared" }) })), 413);
	assert.equal(await enviar(relatorio(fichaHost)), 200);
});

test("placar soma vitorias e guarda a melhor tentativa, sem dados alem do agregado", async () => {
	const { fichaHost, fichaCliente } = await partidaEncerrada();
	await enviar(relatorio(fichaHost, { apelido: "Ilsa", classe: "Mage", tentativas: 3 }));
	await enviar(relatorio(fichaCliente, { apelido: "ilsa", classe: "Mage", tentativas: 1 }));

	const linha = (await lerJson("/placar")).find((jogador) => jogador.apelido.toLowerCase() === "ilsa");

	assert.deepEqual(Object.keys(linha).sort(), ["apelido", "melhor_tentativa", "partidas", "vitorias"]);
	assert.equal(linha.vitorias, 2);
	assert.equal(linha.melhor_tentativa, 1);
});

test("apagar um apelido exige o token e tira o apelido do placar", async () => {
	const { fichaHost } = await partidaEncerrada();
	await enviar(relatorio(fichaHost, { apelido: "Nessa", classe: "Rogue" }));

	const semToken = await fetch(`${HTTP}/jogadores/Nessa`, { method: "DELETE" });
	const comToken = await lerJson("/jogadores/Nessa", { method: "DELETE", headers: { Authorization: `Bearer ${ADMIN}` } });

	assert.equal(semToken.status, 403);
	assert.equal(comToken.apagados, 1);
	assert.ok(!(await lerJson("/placar")).some((jogador) => jogador.apelido === "Nessa"));
});

test("a limpeza diaria apaga o que passou da retencao", async () => {
	assert.ok((await lerJson("/placar")).some((jogador) => jogador.apelido === "Veterano"));

	await fetch(`${HTTP}/__scheduled?cron=0+6+*+*+*`);

	assert.ok(!(await lerJson("/placar")).some((jogador) => jogador.apelido === "Veterano"));
});

test("perto do limite do dia, nenhuma sala nova abre", async () => {
	const primeira = conectar(`${WS}/salas?v=1`);
	const resposta = await primeira.primeiro();
	assert.equal(resposta.t, "bem-vindo", JSON.stringify(resposta));

	const segunda = conectar(`${WS}/salas?v=1`);

	assert.match((await segunda.primeiro()).motivo, /limite de uso de hoje/);
	primeira.ws.close();
});
