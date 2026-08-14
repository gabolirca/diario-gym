// =====================================================================
// GymAI · Estimación de calorías a partir de una foto de comida
//
// La imagen entra por el cuerpo de la petición, se manda a Gemini y se
// descarta. No se escribe en Storage, ni en la base, ni en el log. Lo
// único que se guarda es el resultado numérico, en food_scans.
//
// La llave de Gemini vive aquí, como secreto del proyecto. Nunca sale al
// navegador: si estuviera en index.html, cualquiera podría leerla con
// «ver código fuente» y gastarse la cuota.
// =====================================================================
import { createClient } from 'jsr:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MODELO   = Deno.env.get('GEMINI_MODEL') ?? 'gemini-3.6-flash';
const LLAVE    = Deno.env.get('GEMINI_API_KEY') ?? '';
const LIMITE   = Number(Deno.env.get('LIMITE_FOTOS_DIA') ?? '25');
const MAX_BYTES = 4_000_000;                  // ~4 MB ya reducidos en el navegador

const URL_SB  = Deno.env.get('SUPABASE_URL') ?? Deno.env.get('SB_URL') ?? '';
const ANON    = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SB_ANON_KEY') ?? '';
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SB_SERVICE_ROLE_KEY') ?? '';

const responder = (cuerpo: unknown, status = 200) =>
  new Response(JSON.stringify(cuerpo), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  });

const INSTRUCCION = `Eres un nutriólogo estimando la ingesta de una fotografía de comida.

Devuelve la estimación por alimento y el total del plato.

Reglas:
- Estima la PORCIÓN visible, no una porción estándar de receta. Usa las
  referencias del plato, los cubiertos o el vaso para calcular el tamaño.
- Si un alimento está parcialmente tapado, estima solo lo que se ve.
- Si la foto no es comida, pon es_comida en false y todo lo demás en cero.
- La confianza es "alta" solo si distingues claramente cada alimento y su
  cantidad; "baja" si el plato está mezclado, es un guiso, o no puedes
  juzgar el tamaño. Ante la duda, "media".
- En "nota" escribe en español, en una frase, qué es lo más incierto de
  esta estimación. Sé concreto: "no se ve cuánto aceite lleva el arroz"
  es útil; "es una estimación aproximada" no lo es.
- Las calorías deben ser coherentes con los macronutrientes:
  proteína×4 + carbohidratos×4 + grasa×9 ≈ kcal.`;

const ESQUEMA = {
  type: 'object',
  properties: {
    es_comida: { type: 'boolean' },
    alimentos: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          nombre:     { type: 'string' },
          porcion:    { type: 'string' },
          kcal:       { type: 'number' },
          proteina_g: { type: 'number' },
          carbos_g:   { type: 'number' },
          grasa_g:    { type: 'number' },
        },
        required: ['nombre', 'porcion', 'kcal', 'proteina_g', 'carbos_g', 'grasa_g'],
      },
    },
    total: {
      type: 'object',
      properties: {
        kcal:       { type: 'number' },
        proteina_g: { type: 'number' },
        carbos_g:   { type: 'number' },
        grasa_g:    { type: 'number' },
      },
      required: ['kcal', 'proteina_g', 'carbos_g', 'grasa_g'],
    },
    confianza: { type: 'string', enum: ['alta', 'media', 'baja'] },
    nota:      { type: 'string' },
  },
  required: ['es_comida', 'alimentos', 'total', 'confianza', 'nota'],
};

/* La forma exacta de la respuesta ha cambiado entre versiones de la API.
   En vez de apostar por una sola, se buscan las conocidas en orden. */
function textoDeLaRespuesta(j: any): string | null {
  if (typeof j?.output_text === 'string' && j.output_text.trim()) return j.output_text;
  const deSalida = j?.output?.flatMap?.((o: any) =>
    Array.isArray(o?.content) ? o.content.map((c: any) => c?.text) : [o?.text]);
  const t1 = deSalida?.find?.((t: any) => typeof t === 'string' && t.trim());
  if (t1) return t1;
  const t2 = j?.candidates?.[0]?.content?.parts
    ?.map((p: any) => p?.text).find((t: any) => typeof t === 'string' && t.trim());
  return t2 ?? null;
}

const num = (v: unknown, max: number) => {
  const n = Number(v);
  if (!isFinite(n) || n < 0) return 0;
  return Math.min(Math.round(n * 10) / 10, max);
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST')    return responder({ error: 'Solo POST' }, 405);
  if (!LLAVE)                   return responder({ error: 'El escáner no está configurado todavía.' }, 503);

  // ---------- Quién llama ----------
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return responder({ error: 'Necesitas iniciar sesión.' }, 401);

  const comoUsuario = createClient(URL_SB, ANON, { global: { headers: { Authorization: auth } } });
  const { data: { user } } = await comoUsuario.auth.getUser();
  if (!user) return responder({ error: 'Sesión no válida.' }, 401);

  const admin = createClient(URL_SB, SERVICE, { auth: { persistSession: false } });

  // ---------- Cuota del día, contada en el servidor ----------
  const inicioDelDia = new Date(); inicioDelDia.setHours(0, 0, 0, 0);
  const { count } = await admin.from('food_scans')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user.id)
    .gte('scanned_at', inicioDelDia.toISOString());

  const usadas = count ?? 0;
  if (usadas >= LIMITE) {
    return responder({ error: `Llegaste al límite de ${LIMITE} fotos por día. Captura los datos a mano.`,
                       restantes: 0 }, 429);
  }

  // ---------- Entrada ----------
  let cuerpo: any;
  try { cuerpo = await req.json(); } catch { return responder({ error: 'Petición mal formada.' }, 400); }

  const b64  = String(cuerpo?.imagen ?? '').replace(/^data:[^,]+,/, '');
  const mime = String(cuerpo?.mime ?? 'image/jpeg');
  if (!b64) return responder({ error: 'No llegó ninguna imagen.' }, 400);

  const bytes = Math.floor(b64.length * 3 / 4);
  if (bytes > MAX_BYTES) return responder({ error: 'La foto es demasiado grande.' }, 413);
  if (!['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'].includes(mime))
    return responder({ error: 'Formato de imagen no admitido.' }, 415);

  // ---------- Al modelo ----------
  const t0 = Date.now();
  let r: Response;
  try {
    r = await fetch('https://generativelanguage.googleapis.com/v1beta/interactions', {
      method: 'POST',
      headers: { 'x-goog-api-key': LLAVE, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: MODELO,
        // El texto va ANTES de la imagen: es lo que recomienda la documentación.
        input: [
          { type: 'text',  text: INSTRUCCION },
          { type: 'image', data: b64, mime_type: mime },
        ],
        response_format: { type: 'text', mime_type: 'application/json', schema: ESQUEMA },
      }),
      signal: AbortSignal.timeout(45_000),
    });
  } catch (e) {
    await admin.from('food_scans').insert({ user_id: user.id, model: MODELO, image_bytes: bytes,
      ms: Date.now() - t0, error: 'red: ' + String(e).slice(0, 200) });
    return responder({ error: 'No se pudo contactar al modelo. Intenta de nuevo.' }, 502);
  }

  const ms = Date.now() - t0;

  if (!r.ok) {
    const detalle = (await r.text()).slice(0, 300);
    await admin.from('food_scans').insert({ user_id: user.id, model: MODELO, image_bytes: bytes,
      ms, error: `http ${r.status}: ${detalle}` });
    const mensaje = r.status === 429
      ? 'El modelo está saturado o se agotó la cuota gratuita del día. Captura a mano por ahora.'
      : 'El modelo no pudo analizar la foto.';
    return responder({ error: mensaje }, 502);
  }

  const crudo = textoDeLaRespuesta(await r.json());
  let est: any;
  try { est = JSON.parse(crudo ?? ''); } catch {
    await admin.from('food_scans').insert({ user_id: user.id, model: MODELO, image_bytes: bytes,
      ms, error: 'respuesta ilegible' });
    return responder({ error: 'La respuesta del modelo no se entendió.' }, 502);
  }

  if (est?.es_comida === false) {
    await admin.from('food_scans').insert({ user_id: user.id, model: MODELO, image_bytes: bytes,
      ms, error: 'no es comida' });
    return responder({ error: 'No reconocí comida en esa foto.' }, 422);
  }

  // ---------- Se limpia lo que devolvió el modelo antes de guardarlo ----------
  const total = {
    kcal:       Math.round(num(est?.total?.kcal, 12000)),
    proteina_g: num(est?.total?.proteina_g, 600),
    carbos_g:   num(est?.total?.carbos_g, 1500),
    grasa_g:    num(est?.total?.grasa_g, 500),
  };
  const alimentos = Array.isArray(est?.alimentos) ? est.alimentos.slice(0, 12).map((a: any) => ({
    nombre:     String(a?.nombre ?? '').slice(0, 60),
    porcion:    String(a?.porcion ?? '').slice(0, 40),
    kcal:       Math.round(num(a?.kcal, 12000)),
    proteina_g: num(a?.proteina_g, 600),
    carbos_g:   num(a?.carbos_g, 1500),
    grasa_g:    num(a?.grasa_g, 500),
  })) : [];
  const confianza = ['alta', 'media', 'baja'].includes(est?.confianza) ? est.confianza : 'baja';

  const { data: fila } = await admin.from('food_scans').insert({
    user_id: user.id, model: MODELO, image_bytes: bytes, ms,
    est_kcal: total.kcal, est_protein_g: total.proteina_g,
    est_carbs_g: total.carbos_g, est_fat_g: total.grasa_g,
    est_confidence: confianza, items: alimentos,
  }).select('id').single();

  // Aquí termina la vida de la imagen. Nunca se escribió en ningún lado.
  return responder({
    id: fila?.id ?? null,
    alimentos, total, confianza,
    nota: String(est?.nota ?? '').slice(0, 300),
    modelo: MODELO,
    restantes: Math.max(0, LIMITE - usadas - 1),
  });
});
