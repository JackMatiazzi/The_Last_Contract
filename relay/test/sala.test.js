import { after, before, test } from "node:test";
import assert from "node:assert/strict";
import { escreverRegistros, lerRegistros } from "../src/protocolo.js";
import { derrubar, subirRelay } from "./local.js";

// o relay de verdade no wrangler dev, conversando com ele como o jogo conversaria
const PORTA = 8799;
const BASE = `ws://127.0.0.1:${PORTA}`;
const SALAS_POR_MINUTO_NO_TESTE = 40;
let wrangler;

before(async () => {
	wrangler = await subirRelay(PORTA, { SALAS_POR_IP_POR_MINUTO: SALAS_POR_MINUTO_NO_TESTE, MAX_SALAS: 100, SALAS_ABERTAS_POR_IP: 100, TENTATIVAS_POR_IP_POR_MINUTO: 500, ORCAMENTO_DIARIO: 10000000 });
});

after(() => derrubar(wrangler));

class Jogador {
	constructor(url) {
		this.ws = new WebSocket(url);
		this.ws.binaryType = "arraybuffer";
		this.controles = [];
		this.pacotes = [];
		this.fechou = new Promise((resolver) => this.ws.addEventListener("close", (evento) => resolver(evento.code)));
		this.ws.addEventListener("message", (evento) => {
			if (typeof evento.data === "string") {
				this.controles.push(JSON.parse(evento.data));
			} else {
				this.pacotes.push(...lerRegistros(evento.data));
			}
		});
	}

	static host() {
		return new Jogador(`${BASE}/salas?v=1`);
	}

	static cliente(codigo, id) {
		return new Jogador(`${BASE}/salas/${codigo}?v=1&id=${id}`);
	}

	async controle(tipo) {
		await ate(() => this.controles.some((controle) => controle.t === tipo), `controle ${tipo}`);
		return this.controles.find((controle) => controle.t === tipo);
	}

	enviar(registros) {
		this.ws.send(escreverRegistros(registros.map((registro) => ({ canal: 0, modo: 2, ...registro, dados: new Uint8Array(registro.dados) }))));
	}

	fechar() {
		this.ws.close();
	}
}

async function ate(condicao, oQue, limite = 5000) {
	const fim = Date.now() + limite;
	while (!condicao()) {
		if (Date.now() > fim) {
			throw new Error(`tempo esgotado esperando ${oQue}`);
		}
		await new Promise((resolver) => setTimeout(resolver, 20));
	}
}

async function salaCom(clientes) {
	const host = Jogador.host();
	const { sala } = await host.controle("bem-vindo");
	const outros = [];
	for (const id of clientes) {
		const cliente = Jogador.cliente(sala, id);
		await cliente.controle("bem-vindo");
		outros.push(cliente);
	}
	return { host, sala, clientes: outros };
}

test("o host recebe o id 1 e um codigo de sala", async () => {
	const host = Jogador.host();

	const boasVindas = await host.controle("bem-vindo");

	assert.equal(boasVindas.id, 1);
	assert.match(boasVindas.sala, /^[A-Z2-9]{6}$/);
	assert.deepEqual(boasVindas.pares, []);
	host.fechar();
});

test("quem entra conhece quem ja esta e todos ficam sabendo", async () => {
	const { host, sala, clientes } = await salaCom([500]);

	const novo = Jogador.cliente(sala, 600);
	const boasVindas = await novo.controle("bem-vindo");

	assert.deepEqual(boasVindas.pares.sort(), [1, 500]);
	await ate(() => host.controles.some((controle) => controle.t === "entrou" && controle.id === 600), "host saber do 600");
	await ate(() => clientes[0].controles.some((controle) => controle.t === "entrou" && controle.id === 600), "500 saber do 600");
	[host, novo, ...clientes].forEach((jogador) => jogador.fechar());
});

test("pacote para todos chega aos outros com o remetente carimbado pela sala", async () => {
	const { host, clientes } = await salaCom([500, 600]);

	clientes[0].enviar([{ par: 0, dados: [7, 7] }]);

	await ate(() => host.pacotes.length === 1 && clientes[1].pacotes.length === 1, "entrega");
	assert.equal(host.pacotes[0].par, 500);
	assert.deepEqual([...clientes[1].pacotes[0].dados], [7, 7]);
	assert.equal(clientes[0].pacotes.length, 0);
	[host, ...clientes].forEach((jogador) => jogador.fechar());
});

test("varios pacotes numa mensagem chegam separados a cada destino", async () => {
	const { host, clientes } = await salaCom([500, 600]);

	host.enviar([{ par: 500, dados: [1] }, { par: 600, dados: [2] }, { par: -600, dados: [3] }]);

	await ate(() => clientes[0].pacotes.length === 2 && clientes[1].pacotes.length === 1, "entrega por destino");
	assert.deepEqual(clientes[0].pacotes.map((pacote) => pacote.dados[0]), [1, 3]);
	assert.deepEqual(clientes[1].pacotes.map((pacote) => [pacote.par, pacote.dados[0]]), [[1, 2]]);
	[host, ...clientes].forEach((jogador) => jogador.fechar());
});

test("o quinto jogador e recusado com o motivo", async () => {
	const { host, sala, clientes } = await salaCom([500, 600, 700]);

	const quinto = Jogador.cliente(sala, 800);

	assert.equal((await quinto.controle("erro")).motivo, "A sala está cheia.");
	[host, ...clientes].forEach((jogador) => jogador.fechar());
});

test("sala trancada no inicio da partida nao aceita mais ninguem", async () => {
	const { host, sala } = await salaCom([]);

	host.ws.send(JSON.stringify({ t: "trancar" }));
	await new Promise((resolver) => setTimeout(resolver, 200));
	const atrasado = Jogador.cliente(sala, 500);

	assert.equal((await atrasado.controle("erro")).motivo, "A partida já começou.");
	host.fechar();
});

test("cliente nao tranca a sala nem expulsa ninguem", async () => {
	const { host, sala, clientes } = await salaCom([500, 600]);

	clientes[0].ws.send(JSON.stringify({ t: "trancar" }));
	clientes[0].ws.send(JSON.stringify({ t: "expulsar", id: 600 }));
	await new Promise((resolver) => setTimeout(resolver, 200));
	const novo = Jogador.cliente(sala, 700);

	await novo.controle("bem-vindo");
	assert.equal(clientes[1].ws.readyState, WebSocket.OPEN);
	[host, novo, ...clientes].forEach((jogador) => jogador.fechar());
});

test("codigo inexistente, invalido ou id repetido sao recusados", async () => {
	const { host, sala } = await salaCom([500]);

	assert.match((await Jogador.cliente("ZZZZZZ", 900).controle("erro")).motivo, /não encontrada/);
	assert.match((await Jogador.cliente("abc", 900).controle("erro")).motivo, /inválido/);
	assert.match((await Jogador.cliente(sala, 500).controle("erro")).motivo, /inválido/);
	assert.match((await Jogador.cliente(sala, 1).controle("erro")).motivo, /inválido/);
	host.fechar();
});

test("versao diferente do jogo e recusada", async () => {
	const antigo = new Jogador(`${BASE}/salas?v=0`);

	assert.match((await antigo.controle("erro")).motivo, /versão/);
});

test("host que encerra a sala derruba todos na hora", async () => {
	const { host, clientes } = await salaCom([500, 600]);
	const inicio = Date.now();

	host.ws.send(JSON.stringify({ t: "encerrar" }));

	const avisos = await Promise.all(clientes.map((cliente) => cliente.controle("encerrada")));
	assert.ok(Date.now() - inicio < 1000, `demorou ${Date.now() - inicio} ms`);
	assert.ok(avisos.every((aviso) => aviso.motivo.includes("encerrou")));
	assert.deepEqual(await Promise.all(clientes.map((cliente) => cliente.fechou)), [4004, 4004]);
});

test("quando o host cai, a sala fecha para todos", async () => {
	const { host, clientes } = await salaCom([500]);

	host.fechar();

	assert.match((await clientes[0].controle("encerrada")).motivo, /saiu/);
	assert.equal(await clientes[0].fechou, 4004);
});

test("cliente que sai vira aviso para os outros", async () => {
	const { host, clientes } = await salaCom([500, 600]);

	clientes[0].fechar();

	await ate(() => host.controles.some((controle) => controle.t === "saiu" && controle.id === 500), "aviso de saida");
	[host, clientes[1]].forEach((jogador) => jogador.fechar());
});

test("mensagem maior que o limite derruba quem mandou", async () => {
	const { host, clientes } = await salaCom([500]);

	clientes[0].enviar([{ par: 0, dados: new Array(70 * 1024).fill(1) }]);

	assert.equal(await clientes[0].fechou, 1009);
	host.fechar();
});

test("mensagem malformada derruba quem mandou", async () => {
	const { host, clientes } = await salaCom([500]);

	clientes[0].ws.send(new Uint8Array([1, 2, 3]));

	assert.equal(await clientes[0].fechou, 4007);
	host.fechar();
});

test("mensagens demais por segundo derrubam quem mandou", async () => {
	const { host, clientes } = await salaCom([500]);

	for (let i = 0; i < 40; i++) {
		clientes[0].enviar([{ par: 1, dados: [i] }]);
	}

	assert.equal(await clientes[0].fechou, 4008);
	host.fechar();
});

test("salas diferentes nao se enxergam", async () => {
	const primeira = await salaCom([500]);
	const segunda = await salaCom([500]);

	primeira.clientes[0].enviar([{ par: 0, dados: [1] }]);

	await ate(() => primeira.host.pacotes.length === 1, "entrega na primeira sala");
	await new Promise((resolver) => setTimeout(resolver, 200));
	assert.equal(segunda.host.pacotes.length, 0);
	assert.notEqual(primeira.sala, segunda.sala);
	[primeira, segunda].forEach(({ host, clientes }) => [host, ...clientes].forEach((jogador) => jogador.fechar()));
});

// por ultimo: depois deste teste o IP local fica sem poder criar sala por um minuto
test("quem cria salas demais num minuto e barrado", async () => {
	let motivo = "";
	for (let i = 0; i <= SALAS_POR_MINUTO_NO_TESTE && !motivo; i++) {
		const host = Jogador.host();
		await ate(() => host.controles.length > 0, "resposta da sala");
		motivo = host.controles[0].t === "erro" ? host.controles[0].motivo : "";
		host.fechar();
	}

	assert.match(motivo, /Muitas salas/);
});
