// Os jogos de alguém na Steam, para a biblioteca do grupo.
//
// Quem chama é o app, com a pessoa logada (verify_jwt ligado). A chave da
// Steam Web API fica nos segredos da função (STEAM_API_KEY) e nunca vai para
// o app. Recebe o perfil — o ID de 17 dígitos ou o nome personalizado, que o
// app já tirou do link — e devolve os jogos, do mais jogado para o menos.
//
// O perfil e a lista de jogos precisam estar públicos na Steam; quando não
// estão, a resposta diz isso em português, para o app mostrar.
//
// Com {categorias: [appId, ...]} devolve, em vez disso, as categorias da loja
// de cada jogo (só um jogador, co-op, PvP...), de onde o app chuta quantos
// jogam. A loja é pública: esse modo não precisa da chave.

const chave = Deno.env.get('STEAM_API_KEY');
const api = 'https://api.steampowered.com';

function erro(mensagem: string, status: number): Response {
  return Response.json({ erro: mensagem }, { status });
}

// A loja responde um jogo por vez e segura quem pede demais: os primeiros
// 30, todos de uma vez.
const maximoDeCategorias = 30;

async function categoriasDaLoja(appIds: unknown[]): Promise<Response> {
  const ids = appIds
    .map(Number)
    .filter((id) => Number.isInteger(id) && id > 0)
    .slice(0, maximoDeCategorias);
  const pares = await Promise.all(ids.map(async (id) => {
    try {
      const resposta = await fetch(
        `https://store.steampowered.com/api/appdetails?appids=${id}` +
          '&filters=categories',
      );
      const corpo = await resposta.json();
      const dados = corpo?.[id]?.success ? corpo[id].data : null;
      const categorias = (dados?.categories ?? []) as { id: number }[];
      return categorias.length ? [[id, categorias.map((c) => c.id)]] : [];
    } catch {
      // Jogo que a loja não deu fica de fora; o app usa a faixa larga.
      return [];
    }
  }));
  return Response.json({ categorias: Object.fromEntries(pares.flat()) });
}

Deno.serve(async (req) => {
  const pedido = await req.json().catch(() => ({})) as {
    perfil?: string;
    categorias?: unknown[];
  };
  if (Array.isArray(pedido.categorias)) {
    return categoriasDaLoja(pedido.categorias);
  }

  if (!chave) {
    return erro('A importação da Steam ainda não foi ligada no servidor.', 503);
  }

  let steamid = String(pedido.perfil ?? '').trim();
  if (!steamid) return erro('Faltou o perfil da Steam.', 400);

  // Nome personalizado (steamcommunity.com/id/<nome>) vira o ID de 17 dígitos.
  if (!/^\d{17}$/.test(steamid)) {
    const resposta = await fetch(
      `${api}/ISteamUser/ResolveVanityURL/v1/?key=${chave}` +
        `&vanityurl=${encodeURIComponent(steamid)}`,
    );
    const corpo = await resposta.json().catch(() => null);
    if (corpo?.response?.success !== 1) {
      return erro('Não achei esse perfil na Steam.', 404);
    }
    steamid = corpo.response.steamid;
  }

  const resposta = await fetch(
    `${api}/IPlayerService/GetOwnedGames/v1/?key=${chave}&steamid=${steamid}` +
      '&include_appinfo=1&include_played_free_games=1',
  );
  if (!resposta.ok) return erro('A Steam não respondeu agora.', 502);
  const corpo = await resposta.json().catch(() => null);
  const jogos = corpo?.response?.games as
    | { appid: number; name: string; playtime_forever?: number }[]
    | undefined;
  // Perfil privado chega como resposta vazia, sem a lista.
  if (!jogos) {
    return erro('O perfil ou a lista de jogos está privada na Steam.', 403);
  }

  return Response.json({
    steamid,
    jogos: jogos
      .map((j) => ({
        appId: j.appid,
        nome: j.name,
        horas: Math.round((j.playtime_forever ?? 0) / 60),
      }))
      .sort((a, b) => b.horas - a.horas),
  });
});
