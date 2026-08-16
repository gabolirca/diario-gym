// =====================================================================
// GymAI · Platillos concretos para un plan de equivalentes
//
// La estructura del día NO la decide el modelo: ya viene calculada por la
// app a partir de las calorías y la proteína objetivo, usando el Sistema
// Mexicano de Alimentos Equivalentes. Aquí solo se le pide a Gemini que
// proponga QUÉ COMER para cumplir exactamente esos equivalentes.
//
// Esa separación es deliberada. Si el modelo decidiera las cantidades,
// habría que confiar en unas calorías que se inventó. Al fijarlas antes,
// las cifras siguen siendo del SMAE y el modelo solo aporta variedad.
// =====================================================================
import { createClient } from 'jsr:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MODELO = Deno.env.get('GEMINI_MODEL') ?? 'gemini-3.6-flash';
const LLAVE  = Deno.env.get('GEMINI_API_KEY') ?? '';
const URL_SB = Deno.env.get('SUPABASE_URL') ?? '';
const ANON   = Deno.env.get('SUPABASE_ANON_KEY') ?? '';

const responder = (c: unknown, status = 200) =>
  new Response(JSON.stringify(c), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

const ESQUEMA = {
  type: 'object',
  properties: {
    tiempos: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          tiempo:   { type: 'string', enum: ['desayuno', 'comida', 'cena'] },
          platillo: { type: 'string' },
          ingredientes: { type: 'array', items: { type: 'string' } },
          cumple:   { type: 'string' },
        },
        required: ['tiempo', 'platillo', 'ingredientes', 'cumple'],
      },
    },
    nota: { type: 'string' },
  },
  required: ['tiempos', 'nota'],
};

const GRUPOS: Record<string, string> = {
  verdura: 'verduras', fruta: 'frutas', cereal: 'cereales y tubérculos sin grasa',
  leguminosa: 'leguminosas', aoa: 'alimentos de origen animal muy bajos en grasa',
  leche: 'leche descremada', grasa: 'aceites y grasas',
};

function describir(rep: any): string {
  return ['desayuno', 'comida', 'cena'].map(t => {
    const g = rep?.[t] ?? {};
    const partes = Object.keys(GRUPOS)
      .filter(k => (g[k] ?? 0) > 0)
      .map(k => `${g[k]} de ${GRUPOS[k]}`);
    return `${t.toUpperCase()}: ${partes.join(', ') || 'nada asignado'}`;
  }).join('\n');
}

/* Misma estrategia que en el escáner: la forma de la respuesta ha cambiado
   entre versiones de la API, así que se recorre el árbol buscando el objeto
   con la forma esperada en vez de apostar por una ruta concreta. */
function menuDeLaRespuesta(j: any): any | null {
  const parece = (o: any) => !!o && typeof o === 'object' && Array.isArray(o.tiempos);
  const vistos = new Set<any>(); const pila: any[] = [j]; const textos: string[] = [];
  while (pila.length) {
    const n = pila.pop();
    if (n == null) continue;
    if (typeof n === 'string') { if (n.length < 20000) textos.push(n); continue; }
    if (typeof n !== 'object' || vistos.has(n)) continue;
    vistos.add(n);
    if (parece(n)) return n;
    for (const v of Object.values(n)) pila.push(v);
  }
  for (const t of textos) {
    const limpio = t.trim().replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();
    if (!limpio.startsWith('{')) continue;
    try { const o = JSON.parse(limpio); if (parece(o)) return o; } catch { /* sigue */ }
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST')    return responder({ error: 'Solo POST' }, 405);
  if (!LLAVE) return responder({ error: 'El sugeridor de platillos no está configurado todavía.' }, 503);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return responder({ error: 'Necesitas iniciar sesión.' }, 401);

  const sb = createClient(URL_SB, ANON, { global: { headers: { Authorization: auth } } });
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return responder({ error: 'Sesión no válida.' }, 401);

  const cuerpo = await req.json().catch(() => ({}));
  const rep = cuerpo?.reparto;
  if (!rep?.desayuno) return responder({ error: 'Falta el plan de equivalentes.' }, 400);

  const evitar = String(cuerpo?.evitar ?? '').slice(0, 200);

  const instruccion = `Eres un nutriólogo mexicano armando un menú de un día.

El plan de equivalentes YA ESTÁ CALCULADO y no se toca. Tu única tarea es proponer
un platillo concreto por tiempo de comida que cumpla EXACTAMENTE esos equivalentes,
usando el Sistema Mexicano de Alimentos Equivalentes.

${describir(rep)}

Reglas:
- Comida mexicana común y barata, de la que se consigue en cualquier mercado.
- En "ingredientes" pon la cantidad en medida casera y entre paréntesis a qué
  equivalente corresponde. Ejemplo: "2 tortillas de maíz (2 cereales)".
- Los equivalentes de cada tiempo tienen que sumar exactamente lo indicado arriba.
  No añadas ni quites grupos.
- NO escribas calorías ni gramos de macronutrimentos: esos ya están definidos por
  el sistema de equivalentes y ponerlos otra vez solo introduce errores.
- En "cumple" escribe en una frase por qué ese platillo cubre los equivalentes.
- En "nota" escribe un consejo práctico de preparación o compra, en una frase.
${evitar ? `- La persona pidió evitar: ${evitar}. Respétalo.` : ''}`;

  let r: Response;
  const t0 = Date.now();
  try {
    r = await fetch('https://generativelanguage.googleapis.com/v1beta/interactions', {
      method: 'POST',
      headers: { 'x-goog-api-key': LLAVE, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: MODELO,
        input: [{ type: 'text', text: instruccion }],
        response_format: { type: 'text', mime_type: 'application/json', schema: ESQUEMA },
        store: false,
        generation_config: { thinking_level: 'minimal' },
      }),
      signal: AbortSignal.timeout(45_000),
    });
  } catch {
    return responder({ error: 'No se pudo contactar al modelo. Intenta de nuevo.' }, 502);
  }

  if (!r.ok) {
    return responder({ error: r.status === 429
      ? 'Se agotó la cuota del día. El plan de equivalentes sigue sirviendo sin esto.'
      : 'El modelo no pudo armar el menú.' }, 502);
  }

  const menu = menuDeLaRespuesta(await r.json());
  if (!menu) return responder({ error: 'La respuesta del modelo no se entendió.' }, 502);

  const tiempos = (menu.tiempos ?? []).slice(0, 3).map((t: any) => ({
    tiempo:   ['desayuno','comida','cena'].includes(t?.tiempo) ? t.tiempo : 'comida',
    platillo: String(t?.platillo ?? '').slice(0, 120),
    ingredientes: (Array.isArray(t?.ingredientes) ? t.ingredientes : [])
                    .slice(0, 12).map((i: any) => String(i).slice(0, 120)),
    cumple:   String(t?.cumple ?? '').slice(0, 240),
  }));

  return responder({
    tiempos,
    nota: String(menu.nota ?? '').slice(0, 300),
    modelo: MODELO,
    ms: Date.now() - t0,
  });
});
