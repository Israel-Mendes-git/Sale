// Os jogos de alguém na Steam, para a biblioteca do grupo.
//
// Quem chama é o app, com a pessoa logada (verify_jwt ligado). A chave da
// Steam Web API fica nos segredos da função (STEAM_API_KEY) e nunca vai para
// o app. Recebe o perfil — o ID de 17 dígitos ou o nome personalizado, que o
// app já tirou do link — e devolve os jogos, do mais jogado para o menos.
//
// O perfil e a lista de jogos precisam estar públicos na Steam; quando não
// estão, a resposta diz isso em português, para o app mostrar.

const chave = Deno.env.get('STEAM_API_KEY');
const api = 'https://api.steampowered.com';

function erro(mensagem: string, status: number): Response {
  return Response.json({ erro: mensagem }, { status });
}

Deno.serve(async (req) => {
  if (!chave) {
    return erro('A importação da Steam ainda não foi ligada no servidor.', 503);
  }

  const { perfil } = await req.json().catch(() => ({})) as { perfil?: string };
  let steamid = String(perfil ?? '').trim();
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
