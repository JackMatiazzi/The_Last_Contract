import { spawn, spawnSync } from "node:child_process";
import { rmSync } from "node:fs";
import { fileURLToPath } from "node:url";

// sobe o relay de verdade com o wrangler dev, cada teste com o seu banco D1 local zerado
export const PASTA = fileURLToPath(new URL("..", import.meta.url));

export function wranglerSincrono(argumentos) {
	const resultado = spawnSync("npx", ["wrangler", ...argumentos], { cwd: PASTA, shell: true, encoding: "utf8" });
	if (resultado.status !== 0) {
		throw new Error(`wrangler ${argumentos.join(" ")} falhou:\n${resultado.stdout}\n${resultado.stderr}`);
	}
	return resultado.stdout;
}

export async function subirRelay(porta, variaveis = {}, comandosAntes = []) {
	const estado = `.wrangler/teste-${porta}`;
	rmSync(new URL(`../${estado}`, import.meta.url), { recursive: true, force: true });
	wranglerSincrono(["d1", "migrations", "apply", "DB", "--local", "--persist-to", estado]);
	for (const comando of comandosAntes) {
		wranglerSincrono(["d1", "execute", "DB", "--local", "--persist-to", estado, "--command", `"${comando}"`]);
	}
	const vars = Object.entries(variaveis).flatMap(([nome, valor]) => ["--var", `${nome}:${valor}`]);
	const processo = spawn("npx", ["wrangler", "dev", "--port", String(porta), "--ip", "127.0.0.1", "--persist-to", estado, "--test-scheduled", ...vars], { cwd: PASTA, shell: true, stdio: "pipe" });
	await new Promise((pronto, falhou) => {
		const limite = setTimeout(() => falhou(new Error("wrangler dev nao subiu")), 60000);
		processo.stdout.on("data", (pedaco) => {
			if (pedaco.toString().includes("Ready on")) {
				clearTimeout(limite);
				pronto();
			}
		});
	});
	return processo;
}

export function derrubar(processo) {
	if (process.platform === "win32") {
		spawn("taskkill", ["/pid", String(processo.pid), "/T", "/F"]);
	} else {
		processo.kill();
	}
}
