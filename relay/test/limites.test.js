import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { request } from "node:http";
import { fileURLToPath } from "node:url";

// o relay com os limites de producao: protege a cota do dia contra abuso de um PC so
const PORTA = 8798;
const BASE = `ws://127.0.0.1:${PORTA}`;
const PASTA = fileURLToPath(new URL("..", import.meta.url));
let wrangler;

before(async () => {
	wrangler = spawn("npx", ["wrangler", "dev", "--port", String(PORTA), "--ip", "127.0.0.1"], { cwd: PASTA, shell: true, stdio: "pipe" });
	await new Promise((pronto, falhou) => {
		const limite = setTimeout(() => falhou(new Error("wrangler dev nao subiu")), 60000);
		wrangler.stdout.on("data", (pedaco) => {
			if (pedaco.toString().includes("Ready on")) {
				clearTimeout(limite);
				pronto();
			}
		});
	});
});

after(() => {
	if (process.platform === "win32") {
		spawn("taskkill", ["/pid", String(wrangler.pid), "/T", "/F"]);
	} else {
		wrangler.kill();
	}
});

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

test("tentar codigos sem parar e barrado antes de acordar salas", async () => {
	let motivo = "";
	for (let i = 0; i < 25 && !/Muitas tentativas/.test(motivo); i++) {
		motivo = (await primeiroControle(`${BASE}/salas/ZZZZZ${"ABCDEFGHJKMNPQRSTUVWXYZ"[i]}?v=1&id=77`)).controle.motivo;
	}

	assert.match(motivo, /Muitas tentativas/);
});
