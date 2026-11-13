import { DurableObject } from "cloudflare:workers";
import { abrirPartida, descartarPartida, diaUtc, usoDoDia } from "./banco.js";
import { novoCodigo } from "./protocolo.js";
import { LIMITES } from "./sala.js";

// padroes de producao; o teste local sobe o relay com outros valores (wrangler dev --var)
const PADROES = {
	MAX_SALAS: 8,
	SALAS_POR_IP_POR_MINUTO: 5,
	SALAS_ABERTAS_POR_IP: 2,
	TENTATIVAS_POR_IP_POR_MINUTO: 20,
	RELATORIOS_POR_IP_POR_MINUTO: 10,
	// metade das 100 mil requisicoes gratis; sala aberta ainda nao gravou o consumo, entra pela estimativa
	// (uma partida de 45 min com 4 jogadores mediu 1.971; a margem cobre partidas mais agitadas)
	ORCAMENTO_DIARIO: 50000,
	ESTIMATIVA_SALA_ABERTA: 4000,
	// um PC so nao gasta o dia de todo mundo: passou disso, so cria sala no dia seguinte
	ORCAMENTO_POR_IP: 15000,
};
const MINUTO = 60 * 1000;

// uma instancia so ("global"): sorteia codigos sem repetir, segura o numero de salas abertas e filtra
// quem tenta entrar, para um abuso nao gastar a cota do dia nem acordar salas que nao existem.
// O IP fica so na memoria, pelo tempo do limite, e nunca e gravado (LGPD)
export class Registro extends DurableObject {
	constructor(ctx, env) {
		super(ctx, env);
		this.janelas = new Map();
		this.salasPorIp = new Map();
		this.ipDaSala = new Map();
		this.consumoPorIp = new Map();
	}

	limite(nome) {
		const numero = Number(this.env[nome]);
		return Number.isInteger(numero) && numero > 0 ? numero : PADROES[nome];
	}

	async reservar(ip) {
		const agora = Date.now();
		const chave = chaveDoIp(ip);
		const recusa = (await this.motivoParaNaoCriar(chave, agora)) ?? null;
		if (recusa) {
			return { erro: recusa };
		}
		// o banco vem antes de ler as salas: entre um await do D1 e o put, outra reserva poderia gravar por cima
		const partida = await this.abrirPartidaSePossivel(agora);
		const salas = await this.salasAbertas(agora);
		if (Object.keys(salas).length >= this.limite("MAX_SALAS")) {
			await descartarPartida(this.env.DB, partida).catch((erro) => console.error(JSON.stringify({ evento: "banco-indisponivel", etapa: "descarte", erro: String(erro) })));
			return { erro: "Todas as salas estão ocupadas agora. Tente de novo em alguns minutos." };
		}
		let codigo = novoCodigo();
		while (codigo in salas) {
			codigo = novoCodigo();
		}
		await this.ctx.storage.put("salas", { ...salas, [codigo]: agora });
		this.registrarCriacao(chave, codigo, agora);
		return { codigo, partida };
	}

	async motivoParaNaoCriar(chave, agora) {
		if (!this.dentroDaJanela("criar", chave, "SALAS_POR_IP_POR_MINUTO", agora)) {
			return "Muitas salas criadas em pouco tempo. Espere um minuto.";
		}
		const salas = await this.salasAbertas(agora);
		if (Object.keys(salas).length >= this.limite("MAX_SALAS")) {
			return "Todas as salas estão ocupadas agora. Tente de novo em alguns minutos.";
		}
		const minhas = (this.salasPorIp.get(chave) ?? []).filter((codigo) => codigo in salas);
		if (minhas.length >= this.limite("SALAS_ABERTAS_POR_IP")) {
			return "Você já tem salas abertas. Feche uma antes de criar outra.";
		}
		if ((this.consumoPorIp.get(`${diaUtc(agora)}|${chave}`) ?? 0) >= this.limite("ORCAMENTO_POR_IP")) {
			return "Esta rede já usou a sala online demais hoje. Volta às 21h (horário de Brasília).";
		}
		if (await this.semOrcamento(agora, Object.keys(salas).length)) {
			return "O limite de uso de hoje foi atingido. Volta às 21h (horário de Brasília).";
		}
		return null;
	}

	// banco fora do ar nao impede o co-op: a sala abre sem partida no banco (sem placar nessa partida)
	async abrirPartidaSePossivel(agora) {
		const partida = crypto.randomUUID();
		try {
			await abrirPartida(this.env.DB, partida, agora);
			return partida;
		} catch (erro) {
			console.error(JSON.stringify({ evento: "banco-indisponivel", etapa: "reserva", erro: String(erro) }));
			return "";
		}
	}

	async semOrcamento(agora, salasAbertas) {
		try {
			const { requisicoes } = await usoDoDia(this.env.DB, diaUtc(agora));
			const estimativa = (salasAbertas + 1) * this.limite("ESTIMATIVA_SALA_ABERTA");
			return requisicoes + estimativa > this.limite("ORCAMENTO_DIARIO");
		} catch (erro) {
			console.error(JSON.stringify({ evento: "banco-indisponivel", etapa: "orcamento", erro: String(erro) }));
			return false;
		}
	}

	registrarCriacao(chave, codigo, agora) {
		this.salasPorIp.set(chave, [...(this.salasPorIp.get(chave) ?? []), codigo]);
		this.ipDaSala.set(codigo, `${diaUtc(agora)}|${chave}`);
	}

	// quem entra passa aqui antes de acordar a sala: codigo inexistente para no registro
	async entrar(ip, codigo) {
		const agora = Date.now();
		if (!this.dentroDaJanela("entrar", chaveDoIp(ip), "TENTATIVAS_POR_IP_POR_MINUTO", agora)) {
			return { erro: "Muitas tentativas de entrar. Espere um minuto." };
		}
		const salas = await this.salasAbertas(agora);
		return codigo in salas ? {} : { erro: "Sala não encontrada. Confira o código." };
	}

	// relatorio sem ficha valida custa pouco, mas cada um e uma requisicao do Worker
	async podeRelatar(ip) {
		return this.dentroDaJanela("relatar", chaveDoIp(ip), "RELATORIOS_POR_IP_POR_MINUTO", Date.now());
	}

	// a sala devolve a vaga e diz quanto gastou; o gasto entra na conta do dia de quem criou
	async liberar(codigo, requisicoes = 0) {
		const { [codigo]: _liberada, ...restantes } = await this.salasAbertas(Date.now());
		await this.ctx.storage.put("salas", restantes);
		const dono = this.ipDaSala.get(codigo);
		if (dono) {
			this.consumoPorIp.set(dono, (this.consumoPorIp.get(dono) ?? 0) + requisicoes);
			this.ipDaSala.delete(codigo);
		}
		for (const [chave, codigos] of this.salasPorIp) {
			const sobra = codigos.filter((outro) => outro !== codigo);
			if (sobra.length > 0) {
				this.salasPorIp.set(chave, sobra);
			} else {
				this.salasPorIp.delete(chave);
			}
		}
		this.esquecerDiasPassados();
	}

	// sala que passou da duracao maxima ja foi fechada pela propria sala; aqui so sai da conta.
	// Sala que fechou sem avisar (queda do Worker) tambem sai por aqui depois do prazo
	async salasAbertas(agora) {
		const salas = (await this.ctx.storage.get("salas")) ?? {};
		return Object.fromEntries(Object.entries(salas).filter(([, criada]) => agora - criada < LIMITES.duracaoMs + LIMITES.verificacaoMs));
	}

	// janela de um minuto por IP e por acao; IP sem acao recente sai do mapa, para ele nao crescer para sempre
	dentroDaJanela(acao, chave, limite, agora) {
		const nome = `${acao}|${chave}`;
		const recentes = (this.janelas.get(nome) ?? []).filter((momento) => agora - momento < MINUTO);
		for (const [outra, momentos] of this.janelas) {
			if (momentos.every((momento) => agora - momento >= MINUTO)) {
				this.janelas.delete(outra);
			}
		}
		if (recentes.length >= this.limite(limite)) {
			return false;
		}
		this.janelas.set(nome, [...recentes, agora]);
		return true;
	}

	esquecerDiasPassados() {
		const hoje = diaUtc(Date.now());
		for (const nome of this.consumoPorIp.keys()) {
			if (!nome.startsWith(hoje)) {
				this.consumoPorIp.delete(nome);
			}
		}
	}
}

// IPv6 muda dentro da mesma rede (/64); limitar por endereco inteiro deixaria um PC so passar do limite
export function chaveDoIp(ip) {
	if (!ip.includes(":")) {
		return ip;
	}
	const grupos = ip.split("::")[0].split(":");
	return grupos.slice(0, 4).join(":") + "::/64";
}
