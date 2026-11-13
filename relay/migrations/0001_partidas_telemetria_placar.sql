-- Banco da sala online: consumo de cada partida (orcamento do dia), telemetria do playtest e placar.
-- Datas em milissegundos (INTEGER); "dia" e a data UTC do inicio, igual a virada da cota do Cloudflare.
-- O apelido e dado pessoal (LGPD): fica so o que o placar e o playtest usam, e tudo sai em RETENCAO_DIAS.
-- Os limites dos CHECKs batem com relatorio.js, que recusa antes de chegar aqui.

CREATE TABLE partidas (
	id TEXT PRIMARY KEY,
	dia TEXT NOT NULL,
	inicio INTEGER NOT NULL,
	fim INTEGER,
	minutos REAL,
	jogadores INTEGER NOT NULL DEFAULT 1 CHECK (jogadores BETWEEN 1 AND 4),
	mensagens INTEGER NOT NULL DEFAULT 0 CHECK (mensagens >= 0),
	bytes INTEGER NOT NULL DEFAULT 0 CHECK (bytes >= 0),
	requisicoes INTEGER NOT NULL DEFAULT 0 CHECK (requisicoes >= 0)
) STRICT;

-- cobre a soma do orcamento do dia e o apagamento por idade
CREATE INDEX partidas_dia ON partidas (dia, requisicoes, fim);

-- so o hash da ficha: quem le o banco nao consegue mandar relatorio no lugar do jogador
CREATE TABLE fichas (
	hash TEXT PRIMARY KEY,
	partida_id TEXT NOT NULL REFERENCES partidas (id) ON DELETE CASCADE,
	criada INTEGER NOT NULL,
	usada INTEGER
) STRICT;

CREATE INDEX fichas_partida ON fichas (partida_id);
CREATE INDEX fichas_criada ON fichas (criada);

-- apelido como o jogador digitou, para mostrar; apelido_chave normalizado (NFC, minusculas), para agrupar
-- e apagar: "José" e "JOSÉ" sao o mesmo jogador
CREATE TABLE telemetria (
	id INTEGER PRIMARY KEY,
	partida_id TEXT NOT NULL REFERENCES partidas (id) ON DELETE CASCADE,
	apelido TEXT NOT NULL CHECK (length(apelido) BETWEEN 1 AND 16),
	apelido_chave TEXT NOT NULL,
	classe TEXT NOT NULL,
	resultado TEXT NOT NULL,
	tentativas INTEGER NOT NULL CHECK (tentativas BETWEEN 1 AND 999),
	mortes INTEGER NOT NULL CHECK (mortes BETWEEN 0 AND 9999),
	minutos REAL NOT NULL CHECK (minutos BETWEEN 0 AND 240),
	dados TEXT NOT NULL CHECK (json_valid(dados) AND length(CAST(dados AS BLOB)) <= 16384),
	criada INTEGER NOT NULL
) STRICT;

CREATE INDEX telemetria_partida ON telemetria (partida_id);
CREATE INDEX telemetria_chave ON telemetria (apelido_chave);

-- placar ja somado: atualizado junto com cada relatorio e recontado pela limpeza diaria (o MIN da melhor
-- tentativa nao se desfaz subtraindo). O GET /placar le umas 20 linhas, nao a telemetria inteira
CREATE TABLE placar (
	apelido_chave TEXT PRIMARY KEY,
	apelido TEXT NOT NULL,
	partidas INTEGER NOT NULL,
	vitorias INTEGER NOT NULL,
	melhor_tentativa INTEGER
) STRICT;

CREATE INDEX placar_ordem ON placar (vitorias DESC, melhor_tentativa, partidas DESC);
