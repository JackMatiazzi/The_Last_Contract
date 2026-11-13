import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { request } from "node:http";
import { derrubar, subirRelay } from "./local.js";

// o relay com os limites de producao: protege a cota do dia contra abuso de um PC so
const PORTA = 8798;
const BASE = `ws://127.0.0.1:${PORTA}`;
let wrangler;

before(async () => {
	wrangler = await subirRelay(PORTA);
});

after(() => derrubar(wrangler));

function primeiroControle(url) {
	const ws = new WebSocket(url);
	return new Promise((resolver) => {
		ws.addEventListener("message", (evento) => resolver({ ws, controle: JSON.parse(evento.data) }), { once: true });
	});
}

test("pagina de navegador nao usa o relay", async () => {
	const status = await new Promise((resolver) => {
		const pedido = request({ host: "127.0.0.1", port: PORTA, path: "/salas?v=1", headers: { Upgrade: "websocket", Connection: "Upgrade", Origin: "https://site-qualquer.com", "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==", "Sec-WebSocket-Version": "13" } });
		pedido.on("response", (resposta) => {
			resposta.resume();
			resolver(resposta.statusCode);
		});
		pedido.on("upgrade", (_resposta, socket) => {
			socket.destroy();
			resolver(101);
		});
		pedido.on("error", () => resolver(0));
		pedido.end();
	});

	assert.equal(status, 403);
});

test("um PC so nao segura mais de duas salas abertas", async () => {
	const primeira = await primeiroControle(`${BASE}/salas?v=1`);
	const segunda = await primeiroControle(`${BASE}/salas?v=1`);
	const terceira = await primeiroControle(`${BASE}/salas?v=1`);

	assert.equal(primeira.controle.t, "bem-vindo");
	assert.equal(segunda.controle.t, "bem-vindo");
	assert.match(terceira.controle.motivo, /já tem salas abertas/);
	[primeira, segunda, terceira].forEach(({ ws }) => ws.close());
});

test("relatorios sem parar do mesmo PC sao barrados", async () => {
	const status = [];
	for (let i = 0; i < 12; i++) {
		const resposta = await fetch(`http://127.0.0.1:${PORTA}/telemetria`, { method: "POST", body: JSON.stringify({ ficha: "0".repeat(64) }) });
		status.push(resposta.status);
	}

	assert.equal(status.at(-1), 429);
	assert.ok(status.slice(0, 10).every((codigo) => codigo !== 429));
});

test("tentar codigos sem parar e barrado antes de acordar salas", async () => {
	let motivo = "";
	for (let i = 0; i < 25 && !/Muitas tentativas/.test(motivo); i++) {
		motivo = (await primeiroControle(`${BASE}/salas/ZZZZZ${"ABCDEFGHJKMNPQRSTUVWXYZ"[i]}?v=1&id=77`)).controle.motivo;
	}

	assert.match(motivo, /Muitas tentativas/);
});
