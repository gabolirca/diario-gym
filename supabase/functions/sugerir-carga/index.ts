// =====================================================================
// GymAI · Servicio de inferencia: qué peso poner en la próxima sesión
//
// El bosque entrenado en Python se exporta a v2/modelo.json y se evalúa
// aquí. Un árbol de decisión no es más que una lista de comparaciones,
// así que no hace falta Python en producción: el archivo se descarga una
// vez por instancia y se queda en memoria.
//
// Todo pasa por el cliente del usuario, no por la llave de servicio. Así
// las mismas políticas de RLS que protegen la app protegen esto: nadie
// puede pedir predicciones de otra persona ni escribirlas en su nombre.
// =====================================================================
import { createClient } from 'jsr:@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const URL_SB = Deno.env.get('SUPABASE_URL') ?? '';
const ANON   = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const URL_MODELO = Deno.env.get('MODELO_URL') ??
  'https://gabolirca.github.io/diario-gym/v2/modelo.json';

const responder = (c: unknown, status = 200) =>
  new Response(JSON.stringify(c), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

// ---------------------------------------------------------------------
// El modelo se descarga una sola vez por instancia
// ---------------------------------------------------------------------
let MODELO: any = null;
let bajando: Promise<any> | null = null;

async function modelo() {
  if (MODELO) return MODELO;
  if (!bajando) {
    bajando = fetch(URL_MODELO, { signal: AbortSignal.timeout(15_000) })
      .then(r => { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(m => (MODELO = m))
      .finally(() => { bajando = null; });
  }
  return await bajando;
}

// ---------------------------------------------------------------------
// Evaluación del bosque. Mismo código que ml/evaluador.js, que es donde
// se comprueba contra scikit-learn que da el número idéntico.
// ---------------------------------------------------------------------
function vectorDe(fila: any, m: any): number[] {
  const v: number[] = [];
  for (const c of m.numericas) {
    const x = Number(fila[c]);
    v.push(Number.isFinite(x) ? x : m.medianas[c]);
  }
  for (const c of Object.keys(m.categoricas)) {
    const valor = fila[c] == null ? '' : String(fila[c]);
    for (const opcion of m.categoricas[c]) v.push(valor === opcion ? 1 : 0);
  }
  return v;
}

function bajarArbol(t: any, v: number[]): number {
  let n = 0;
  while (t.f[n] >= 0) n = v[t.f[n]] <= t.u[n] ? t.i[n] : t.d[n];
  return t.v[n];
}

const predecirDelta = (m: any, v: number[]) =>
  m.arboles.reduce((s: number, t: any) => s + bajarArbol(t, v), 0) / m.arboles.length;

const redondear = (kg: number, inc: number) => Math.round(kg / inc) * inc;

/* El modelo propone; esta capa impide disparates. Ninguna sugerencia sube
   más de dos discos ni más del 10 %, ni baja más del 20 %. Cuando recorta
   se anota por qué: una recomendación recortada no es lo mismo que una que
   el modelo dio directamente, y para el análisis hay que distinguirlas. */
function limitar(kg: number, actual: number, inc: number) {
  // El redondeo no es cosmético: 100 × 1.10 da 110.00000000000001 en coma
  // flotante, y ese número acabaría impreso en la pantalla del gimnasio.
  const dos = (x: number) => Math.round(x * 100) / 100;
  const techo = Math.min(actual + 2 * inc, actual * 1.10);
  const piso  = actual * 0.80;
  if (kg > techo) return { kg: dos(techo), razon: 'subida mayor al 10 % o a dos discos' };
  if (kg < piso)  return { kg: dos(piso),  razon: 'bajada mayor al 20 %' };
  return { kg: dos(kg), razon: null as string | null };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST')    return responder({ error: 'Solo POST' }, 405);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return responder({ error: 'Necesitas iniciar sesión.' }, 401);

  const sb = createClient(URL_SB, ANON, { global: { headers: { Authorization: auth } } });
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return responder({ error: 'Sesión no válida.' }, 401);

  let m: any;
  try { m = await modelo(); }
  catch (e) { return responder({ error: 'El modelo no está publicado todavía.' }, 503); }

  const cuerpo = await req.json().catch(() => ({}));
  const fecha  = /^\d{4}-\d{2}-\d{2}$/.test(cuerpo?.fecha) ? cuerpo.fecha
               : new Date().toISOString().slice(0, 10);

  // ---------- La versión del modelo que está activa ----------
  const { data: mv } = await sb.from('model_versions')
    .select('id, version').eq('is_active', true).eq('model_kind', 'progresion').maybeSingle();

  // ---------- La última sesión registrada de cada ejercicio ----------
  // v_ml_dataset ya trae todo el historial calculado. Con security_invoker,
  // esta consulta solo puede ver las filas de quien la pide.
  const { data: filas, error } = await sb.from('v_ml_dataset')
    .select('*').order('performed_on', { ascending: false }).limit(600);
  if (error) return responder({ error: 'No se pudo leer el historial.' }, 500);

  const ultima = new Map<number, any>();
  for (const f of filas ?? []) if (!ultima.has(f.exercise_id)) ultima.set(f.exercise_id, f);

  // ---------- Nombres de los ejercicios ----------
  const ids = [...ultima.keys()];
  const { data: exs } = ids.length
    ? await sb.from('exercises').select('id, slug, name').in('id', ids)
    : { data: [] as any[] };
  const nombre = new Map((exs ?? []).map((e: any) => [e.id, e]));

  const sugerencias: any[] = [];
  const sinHistorial: any[] = [];

  for (const [id, f] of ultima) {
    const ex = nombre.get(id) ?? { slug: null, name: null };
    // El umbral viaja dentro del modelo: si mañana se reentrena pidiendo más
    // o menos historial, no hay que tocar esta función.
    const minSes = Number(m.min_sesiones) || 2;
    if (Number(f.session_no) < minSes) {
      sinHistorial.push({ exercise_id: id, slug: ex.slug, nombre: ex.name,
                          sesiones: Number(f.session_no) || 0,
                          faltan: minSes - (Number(f.session_no) || 0) });
      continue;
    }
    const actual = Number(f.top_weight_kg);
    const inc    = Number(f.load_increment_kg) || 2.5;
    if (!Number.isFinite(actual) || actual <= 0) continue;

    const delta  = predecirDelta(m, vectorDe(f, m));
    const crudo  = actual + delta;
    const lim    = limitar(redondear(crudo, inc), actual, inc);

    sugerencias.push({
      exercise_id: id, slug: ex.slug, nombre: ex.name,
      actual, sugerido: lim.kg, cambio: +(lim.kg - actual).toFixed(2),
      crudo: +crudo.toFixed(3),          // antes de redondear al disco y de recortar
      incremento: inc, recortado: lim.razon != null, razon: lim.razon,
      ultima_sesion: f.performed_on, rir_ultima: f.avg_rir,
    });
  }

  // ---------- Se guarda lo que se predijo, antes de saber si acertó ----------
  // Registrarlo por adelantado es lo que hace la evaluación honesta: el error
  // se calcula después contra lo que la persona levantó de verdad.
  if (sugerencias.length) {
    await sb.from('predictions').delete()
      .eq('user_id', user.id).eq('predicted_for', fecha);

    const { error: ei } = await sb.from('predictions').insert(sugerencias.map(s => ({
      user_id: user.id,
      exercise_id: s.exercise_id,
      model_version_id: mv?.id ?? null,
      predicted_for: fecha,
      predicted_weight_kg: s.sugerido,
      raw_weight_kg: s.crudo,            // lo que dijo el modelo sin redondear ni recortar
      target_rir: ultima.get(s.exercise_id)?.avg_rir ?? null,
      clamped: s.recortado,
      clamp_reason: s.razon,
      features: ultima.get(s.exercise_id),
    })));
    if (ei) return responder({ error: 'No se pudieron guardar las predicciones.' }, 500);
  }

  return responder({
    fecha,
    modelo: mv?.version ?? m.version,
    mae_kg: m.mae_kg,
    entrenado_con: m.entrenado_con,
    sugerencias: sugerencias.sort((a, b) => (a.nombre ?? '').localeCompare(b.nombre ?? '')),
    sin_historial: sinHistorial,
  });
});
