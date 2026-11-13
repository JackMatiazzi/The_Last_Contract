import { DurableObject } from "cloudflare:workers";
import { destinatarios, escreverRegistros, ID_HOST, idDeClienteValido, lerRegistros } from "./protocolo.js";

// o jogo manda no maximo 10 mensagens por segundo; o resto da folga e para rajada de inicio de fase
export const LIMITES = {
	jogadores: 4,
	mensagensPorSegundo: 15,
	bytesPorMensagem: 64 * 1024,
	bytesPorComando: 256,
	mensagensPorSala: 150000,
	ociosaMs: 10 * 60 * 1000,
	semClientesMs: 2 * 60 * 1000,
	duracaoMs: 90 * 60 * 1000,
	verificacaoMs: 60 * 1000,
	gravarACada: 50,
};

// uma sala por partida: cada uma e um Durable Object proprio, entao varias rodam ao mesmo tempo.
// A sala nao entende o jogo: so carimba quem mandou e entrega cada pacote ao destino.
// A memoria some quando a sala hiberna; consumo e ultima atividade ficam guardados no socket do host
export class Sala extends DurableObject {
	constructor(ctx, env) {
		super(ctx, env);
		this.taxa = new Map();
		this.consumo = null;
		this.ultimaAtividade = null;
	}

	async fetch(request) {
		const url = new URL(request.url);
		const codigo = url.searchParams.get("sala");
		const papel = url.searchParams.get("papel");
		const id = papel === "host" ? ID_HOST : Number(url.searchParams.get("id"));
		const recusa = this.motivoDeRecusa(papel, id);
		if (recusa) {
			return recusarConexao(recusa);
		}
		const [cliente, servidor] = Object.values(new WebSocketPair());
		this.ctx.acceptWebSocket(servidor);
		servidor.serializeAttachment({ id, codigo, inicio: Date.now(), trancada: false, teveCliente: false });
		servidor.send(JSON.stringify({ t: "bem-vindo", id, sala: codigo, pares: this.pares().filter((par) => par !== id) }));
		this.avisar({ t: "entrou", id }, id);
		if (papel !== "host") {
			this.atualizarHost({ teveCliente: true });
		}
		this.ultimaAtividade = Date.now();
		if ((await this.ctx.storage.getAlarm()) === null) {
			await this.ctx.storage.setAlarm(Date.now() + LIMITES.verificacaoMs);
		}
		return new Response(null, { status: 101, webSocket: cliente });
	}

	motivoDeRecusa(papel, id) {
		const pares = this.pares();
		if (papel === "host") {
			return pares.length > 0 ? "Esse código de sala já está em uso." : null;
		}
		const host = this.host();
		if (!host) {
			return "Sala não encontrada. Confira o código.";
		}
		if (host.deserializeAttachment().trancada) {
			return "A partida já começou.";
		}
		if (pares.length >= LIMITES.jogadores) {
			return "A sala está cheia.";
		}
		return idDeClienteValido(id, pares) ? null : "Identificador de jogador inválido. Tente entrar de novo.";
	}

	async webSocketMessage(ws, mensagem) {
		this.ultimaAtividade = Date.now();
		const tamanho = typeof mensagem === "string" ? mensagem.length : mensagem.byteLength;
		const eu = ws.deserializeAttachment();
		const falha = this.motivoParaDerrubar(ws, eu, mensagem, tamanho);
		if (falha) {
			ws.close(falha.codigo, falha.motivo);
			return;
		}
		if (typeof mensagem === "string") {
			this.controle(mensagem);
			return;
		}
		const registros = lerRegistros(mensagem);
		if (registros === null) {
			ws.close(4007, "mensagem invalida");
			return;
		}
		if (this.contar(tamanho) > LIMITES.mensagensPorSala) {
			await this.expirar("A sala passou do limite de mensagens.");
			return;
		}
		this.entregar(eu.id, registros);
	}

	// so o host fala por texto, e com comandos curtos; o resto e jogo em binario
	motivoParaDerrubar(ws, eu, mensagem, tamanho) {
		if (!this.dentroDaTaxa(ws)) {
			return { codigo: 4008, motivo: "mensagens demais" };
		}
		if (typeof mensagem === "string" && (eu.id !== ID_HOST || tamanho > LIMITES.bytesPorComando)) {
			return { codigo: 4007, motivo: "comando invalido" };
		}
		if (tamanho > LIMITES.bytesPorMensagem) {
			return { codigo: 1009, motivo: "mensagem grande demais" };
		}
		return null;
	}

	contar(bytes) {
		const atual = this.consumoAtual();
		this.consumo = { mensagens: atual.mensagens + 1, bytes: atual.bytes + bytes };
		if (this.consumo.mensagens % LIMITES.gravarACada === 0) {
			this.atualizarHost({ consumo: this.consumo, ultimaAtividade: this.ultimaAtividade });
		}
		return this.consumo.mensagens;
	}

	consumoAtual() {
		return this.consumo ?? this.host()?.deserializeAttachment().consumo ?? { mensagens: 0, bytes: 0 };
	}

	// cada destino recebe uma mensagem so com tudo que veio para ele; o que sai da sala nao e cobrado
	entregar(remetente, registros) {
		const sockets = this.socketsPorId();
		const pares = [...sockets.keys()];
		const porDestino = new Map(pares.map((par) => [par, []]));
		for (const registro of registros) {
			for (const destino of destinatarios(registro.par, remetente, pares)) {
				porDestino.get(destino).push({ ...registro, par: remetente });
			}
		}
		for (const [destino, lista] of porDestino) {
			if (lista.length > 0) {
				enviarSemErro(sockets.get(destino), escreverRegistros(lista));
			}
		}
	}

	// trancar no inicio da partida, tirar alguem e encerrar. Encerrar avisa todos na hora;
	// so fechar a conexao leva alguns segundos para chegar aos outros
	controle(texto) {
		const comando = lerJson(texto);
		if (comando?.t === "encerrar") {
			this.fecharTodos("O host encerrou a partida.", 4004);
		} else if (comando?.t === "trancar") {
			this.atualizarHost({ trancada: true });
		} else if (comando?.t === "expulsar" && Number.isInteger(comando.id) && comando.id !== ID_HOST) {
			const alvo = this.socketsPorId().get(comando.id);
			if (alvo) {
				fecharSemErro(alvo, 4001, "removido pelo host");
			}
		}
	}

	// cada socket fechado aqui volta em webSocketClose; a marca evita avisos e encerramentos repetidos
	fecharTodos(motivo, codigo) {
		const sockets = this.ctx.getWebSockets();
		sockets.forEach((ws) => ws.serializeAttachment({ ...ws.deserializeAttachment(), encerrando: true }));
		for (const ws of sockets) {
			const host = ws.deserializeAttachment().id === ID_HOST;
			if (!host) {
				enviarSemErro(ws, JSON.stringify({ t: "encerrada", motivo }));
			}
			fecharSemErro(ws, host ? 1000 : codigo, motivo);
		}
	}

	async webSocketClose(ws, codigo) {
		await this.sair(ws, codigo);
	}

	async webSocketError(ws) {
		await this.sair(ws, 1011);
	}

	async sair(ws, codigo) {
		this.taxa.delete(ws);
		const eu = ws.deserializeAttachment();
		fecharSemErro(ws, codigo);
		if (eu.encerrando) {
			return;
		}
		const consumo = this.consumoAtual();
		const restantes = this.ctx.getWebSockets().filter((outro) => outro !== ws);
		if (eu.id === ID_HOST) {
			this.fecharTodos("O host saiu da partida.", 4004);
		} else {
			this.avisar({ t: "saiu", id: eu.id }, eu.id);
		}
		if (eu.id === ID_HOST || restantes.length === 0) {
			await this.encerrar(eu.codigo, consumo);
		}
	}

	async alarm() {
		const host = this.host();
		if (!host) {
			return;
		}
		const motivo = this.motivoParaExpirar(host.deserializeAttachment(), Date.now());
		if (motivo) {
			await this.expirar(motivo);
			return;
		}
		await this.ctx.storage.setAlarm(Date.now() + LIMITES.verificacaoMs);
	}

	// sala criada e abandonada sem ninguem entrar ocupa vaga; fecha em 2 minutos, nao em 10
	motivoParaExpirar(dados, agora) {
		const ultima = this.ultimaAtividade ?? dados.ultimaAtividade ?? dados.inicio;
		if (agora - dados.inicio > LIMITES.duracaoMs) {
			return "A sala chegou ao tempo máximo.";
		}
		if (!dados.teveCliente && agora - dados.inicio > LIMITES.semClientesMs) {
			return "Ninguém entrou na sala.";
		}
		return agora - ultima > LIMITES.ociosaMs ? "A sala ficou parada e expirou." : null;
	}

	async expirar(motivo) {
		const host = this.host();
		const consumo = this.consumoAtual();
		if (host) {
			enviarSemErro(host, JSON.stringify({ t: "encerrada", motivo }));
		}
		this.fecharTodos(motivo, 4009);
		if (host) {
			await this.encerrar(host.deserializeAttachment().codigo, consumo);
		}
	}

	// o registro libera a vaga e o consumo da sala fica no log do Worker, para medir o custo real
	async encerrar(codigo, consumo) {
		console.log(JSON.stringify({ evento: "sala-encerrada", ...consumo, requisicoes: Math.ceil(consumo.mensagens / 20) }));
		this.consumo = null;
		await this.ctx.storage.deleteAlarm();
		await this.env.REGISTRO.get(this.env.REGISTRO.idFromName("global")).liberar(codigo);
	}

	dentroDaTaxa(ws) {
		const agora = Date.now();
		const atual = this.taxa.get(ws);
		const janela = atual && agora - atual.inicio < 1000 ? { inicio: atual.inicio, contagem: atual.contagem + 1 } : { inicio: agora, contagem: 1 };
		this.taxa.set(ws, janela);
		return janela.contagem <= LIMITES.mensagensPorSegundo;
	}

	atualizarHost(campos) {
		const host = this.host();
		if (host) {
			host.serializeAttachment({ ...host.deserializeAttachment(), ...campos });
		}
	}

	avisar(controle, exceto) {
		const texto = JSON.stringify(controle);
		for (const [id, ws] of this.socketsPorId()) {
			if (id !== exceto) {
				enviarSemErro(ws, texto);
			}
		}
	}

	socketsPorId() {
		return new Map(this.ctx.getWebSockets().map((ws) => [ws.deserializeAttachment().id, ws]));
	}

	pares() {
		return [...this.socketsPorId().keys()];
	}

	host() {
		return this.socketsPorId().get(ID_HOST) ?? null;
	}
}

// recusa pelo proprio WebSocket: o jogo mostra o motivo em vez de um erro de conexao generico.
// O motivo vai tambem no fechamento (ate 123 bytes): a mensagem logo antes dele pode se perder no cliente
export function recusarConexao(motivo) {
	const [cliente, servidor] = Object.values(new WebSocketPair());
	servidor.accept();
	servidor.send(JSON.stringify({ t: "erro", motivo }));
	servidor.close(4003, motivo);
	return new Response(null, { status: 101, webSocket: cliente });
}

function lerJson(texto) {
	try {
		return JSON.parse(texto);
	} catch {
		return null;
	}
}

// mandar para quem acabou de fechar lanca erro; os outros destinos nao podem ficar sem o pacote por isso
function enviarSemErro(ws, dado) {
	try {
		ws.send(dado);
	} catch (erro) {
		if (!(erro instanceof TypeError)) {
			throw erro;
		}
	}
}

// fechar um socket que o outro lado ja fechou lanca erro; aqui so importa que ele termine fechado
function fecharSemErro(ws, codigo, motivo = "") {
	try {
		ws.close(codigo === 1005 || codigo === 1006 ? 1000 : codigo, motivo);
	} catch (erro) {
		if (!(erro instanceof TypeError)) {
			throw erro;
		}
	}
}
