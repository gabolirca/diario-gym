/* Evalúa el bosque exportado por exportar_modelo.py sin necesidad de Python.
   Es el mismo código que corre dentro de la Edge Function; vive aquí aparte
   para poder comprobar, con la muestra que deja el exportador, que da
   exactamente el mismo número que scikit-learn. */

/* Arma el vector de variables igual que lo armó el Codificador de Python:
   primero las numéricas en orden, rellenando huecos con la mediana del
   entrenamiento, y después las categóricas en uno-de-N. */
function vectorDe(fila, modelo) {
  const v = [];
  for (const c of modelo.numericas) {
    const x = Number(fila[c]);
    v.push(Number.isFinite(x) ? x : modelo.medianas[c]);
  }
  for (const c of Object.keys(modelo.categoricas)) {
    const valor = fila[c] == null ? '' : String(fila[c]);
    for (const opcion of modelo.categoricas[c]) v.push(valor === opcion ? 1 : 0);
  }
  return v;
}

/* Un árbol es una lista de nodos. Se baja desde la raíz comparando una
   variable contra un umbral hasta llegar a una hoja, que lleva el valor. */
function bajarArbol(t, v) {
  let n = 0;
  while (t.f[n] >= 0) n = v[t.f[n]] <= t.u[n] ? t.i[n] : t.d[n];
  return t.v[n];
}

/* El bosque es el promedio de sus árboles. */
function predecirDelta(modelo, v) {
  let s = 0;
  for (const t of modelo.arboles) s += bajarArbol(t, v);
  return s / modelo.arboles.length;
}

/* El modelo predice el CAMBIO de carga. Estas dos capas lo convierten en un
   peso que existe en el gimnasio y que no es una barbaridad. */
const redondear = (kg, inc) => Math.round(kg / inc) * inc;

/* El redondeo final no es cosmético: 100 × 1.10 da 110.00000000000001 en
   coma flotante, y ese número acabaría impreso en la pantalla del gimnasio. */
const limitar = (kg, actual, inc) =>
  Math.round(Math.min(Math.max(kg, actual * 0.80), Math.min(actual + 2 * inc, actual * 1.10)) * 100) / 100;

function sugerir(modelo, fila) {
  const actual = Number(fila.top_weight_kg);
  const inc    = Number(fila.load_increment_kg) || 2.5;
  const delta  = predecirDelta(modelo, vectorDe(fila, modelo));
  return {
    actual,
    sugerido: limitar(redondear(actual + delta, inc), actual, inc),
    delta_crudo: delta,
  };
}

if (typeof module !== 'undefined') {
  module.exports = { vectorDe, bajarArbol, predecirDelta, redondear, limitar, sugerir };
}
