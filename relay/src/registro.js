import { DurableObject } from "cloudflare:workers";
import { novoCodigo } from "./protocolo.js";
import { LIMITES } from "./sala.js";

// padroes de producao; o teste local sobe o relay com valores maiores (wrangler dev --var)
const MAX_SALAS = 8;
const SALAS_POR_IP_POR_MINUTO = 5;
const SALAS_ABERTAS_POR_IP = 2;
const TENTATIVAS_POR_IP_POR_MINUTO = 20;
const MINUTO = 60 * 1000;

// uma instancia so ("global"): sorteia codigos sem repetir, segura o numero de salas abertas e
// filtra quem tenta entrar, para um abuso nao gastar a cota do dia nem acordar salas que nao existem.
// O IP fica so na memoria, pelo tempo do limite, e nunca e gravado
export class Registro extends DurableObject {
	constructor(ctx, env) {
		super(ctx, env);
		this.criacoesPorIp = new Map();
		this.tentativasPorIp = new Map();
		this.salasPorIp = new Map();
	}

	async reservar(ip) {
		const agora = Date.now();
		const chave = chaveDoIp(ip);
		const recentes = recentesDe(this.criacoesPorIp, chave, agora);
		if (recentes.length >= limite(this.env.SALAS_POR_IP_POR_MINUTO, SALAS_POR_IP_POR_MINUTO)) {
			return { erro: "Muitas salas criadas em pouco tempo. Espere um minuto." };
		}
		const salas = await this.salasAbertas(agora);
		const minhas = (this.salasPorIp.get(chave) ?? []).filter((codigo) => codigo in salas);
		if (minhas.length >= limite(this.env.SALAS_ABERTAS_POR_IP, SALAS_ABERTAS_POR_IP)) {
			return { erro: "Você já tem salas abertas. Feche uma antes de criar outra." };
		}
		if (Object.keys(salas).length >= limite(this.env.MAX_SALAS, MAX_SALAS)) {
			return { erro: "Todas as salas estão ocupadas agora. Tente de novo em alguns minutos." };
		}
		let codigo = novoCodigo();
		while (codigo in salas) {
			codigo = novoCodigo();
		}
		await this.ctx.storage.put("salas", { ...salas, [codigo]: agora });
		this.criacoesPorIp.set(chave, [...recentes, agora]);
		this.salasPorIp.set(chave, [...minhas, codigo]);
		return { codigo };
	}

	// quem entra passa aqui antes de acordar a sala: codigo inexistente para no registro
	async entrar(ip, codigo) {
		const agora = Date.now();
		const chave = chaveDoIp(ip);
		const recentes = recentesDe(this.tentativasPorIp, chave, agora);
		if (recentes.length >= limite(this.env.TENTATIVAS_POR_IP_POR_MINUTO, TENTATIVAS_POR_IP_POR_MINUTO)) {
			return { erro: "Muitas tentativas de entrar. Espere um minuto." };
		}
		this.tentativasPorIp.set(chave, [...recentes, agora]);
		const salas = await this.salasAbertas(agora);
		return codigo in salas ? {} : { erro: "Sala não encontrada. Confira o código." };
	}

	async liberar(codigo) {
		const { [codigo]: _liberada, ...restantes } = await this.salasAbertas(Date.now());
		await this.ctx.storage.put("salas", restantes);
		for (const [chave, codigos] of this.salasPorIp) {
			const sobra = codigos.filter((outro) => outro !== codigo);
			if (sobra.length > 0) {
				this.salasPorIp.set(chave, sobra);
			} else {
				this.salasPorIp.delete(chave);
			}
		}
	}

	// sala que passou da duracao maxima ja foi fechada pela propria sala; aqui so sai da conta.
	// Sala que fechou sem avisar (queda do Worker) tambem sai por aqui depois do prazo
	async salasAbertas(agora) {
		const salas = (await this.ctx.storage.get("salas")) ?? {};
		return Object.fromEntries(Object.entries(salas).filter(([, criada]) => agora - criada < LIMITES.duracaoMs + LIMITES.verificacaoMs));
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

// le e ja poda: IP sem tentativa recente sai do mapa, para ele nao crescer para sempre
function recentesDe(mapa, chave, agora) {
	const recentes = (mapa.get(chave) ?? []).filter((momento) => agora - momento < MINUTO);
	for (const [outra, momentos] of mapa) {
		if (momentos.every((momento) => agora - momento >= MINUTO)) {
			mapa.delete(outra);
		}
	}
	return recentes;
}

function limite(valor, padrao) {
	const numero = Number(valor);
	return Number.isInteger(numero) && numero > 0 ? numero : padrao;
}
