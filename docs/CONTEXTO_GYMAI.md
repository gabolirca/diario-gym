# GymAI — contexto completo del proyecto

> Documento de traspaso. Está escrito para que alguien que no ha visto nunca este
> proyecto pueda entenderlo entero y arrancar la versión móvil sin tener que
> reconstruir el razonamiento desde cero.
>
> Fecha: 14 de agosto de 2026 · Autor del proyecto: Gabo (José Gabriel Lira Castelán)

---

## 1. Qué es

**GymAI** es un diario de entrenamiento de gimnasio que además funciona como
instrumento de investigación. Nació de una PWA personal de una sola persona y
creció hasta ser un proyecto académico con dos objetivos: presentarse en una
feria escolar y, más adelante, sostener una publicación en revista indexada.

La idea central: **una app que ajusta la carga de entrenamiento al usuario a
partir de su propio historial, usando un modelo predictivo entrenado**.

### Las hipótesis del estudio

- **H1** — Un modelo entrenado con el historial de la persona (peso, repeticiones
  y RIR) predice mejor la carga de la siguiente sesión que las reglas de
  progresión de uso común.
- **H2** — Añadir variables nutricionales (balance calórico y proteína a 7 días)
  mejora esa predicción.

H2 es la que distingue este proyecto de una app de gimnasio cualquiera, y es la
razón por la que el registro de comida importa tanto en el diseño.

> **Estado honesto de H2**: en los datos sintéticos actuales, quitar las
> variables de nutrición **mejora** el error un 2.1 %. Es decir, hoy la evidencia
> apunta en contra de H2. Puede ser que el generador sintético no modele bien el
> efecto de la nutrición sobre la fuerza a corto plazo, o puede ser que el efecto
> real a dos semanas sea despreciable. Con datos reales se vuelve a medir. **No
> presentar H2 como confirmada.**

---

## 2. Estado actual: dos versiones vivas

| | **v1** | **v2** |
|---|---|---|
| Para qué | Uso personal diario, estable | Desarrollo de las funciones nuevas |
| URL | `gabolirca.github.io/diario-gym/` | `gabolirca.github.io/diario-gym/v2/` |
| Panel investigador | `/diario-gym/panel.html` | `/diario-gym/v2/panel.html` |
| Proyecto Supabase | `ckvogrrzhdfdubqcwayn` (gymai) | `usaosgtherqnqwjhgbtt` (gymai-v2) |
| Clave publicable | `sb_publishable_sTfMoFyH0WHOGpFIlSu1Eg_6yy0QNVX` | `sb_publishable_wSWmaS791JkiAcH8cXmLyw_ONq-gUsK` |
| Clave localStorage | `gymDiary_gabo_v1` | `gymDiary_v2` |
| Tamaño de `index.html` | 120 KB | 152 KB |
| Service worker | `diario-gym-v14` | `diario-gym-v2-007` |

Las dos son **un solo archivo HTML** con CSS y JavaScript en línea, sin
compilación, sin dependencias de npm. La única librería externa es
`@supabase/supabase-js@2`, cargada como módulo ESM desde `esm.sh` en tiempo de
ejecución.

Repositorio: `github.com/gabolirca/diario-gym` (GitHub Pages sirve la raíz).

### Cuentas

- **Participante**: `gabolirac@gmail.com` — tiene el historial real migrado
  desde v1 (4 sesiones, 77 series, 2 nados, 45.1 t de tonelaje).
- **Investigador**: `josegab.lira.castelan020506@gmail.com` — `is_admin = true`.
  Solo lectura sobre todos los participantes; verificado que un `update` desde
  esa cuenta afecta 0 filas.
- **5 participantes de demostración** marcados `is_demo = true`, con seis
  semanas de historial y caducidad automática el 13 de septiembre de 2026.

---

## 3. La IA: dónde está, dónde no, y por qué

Esta es la sección que más importa. En el proyecto conviven **tres cosas muy
distintas** que suelen meterse en el mismo saco de "IA", y confundirlas sería un
problema serio si un revisor pregunta.

### Tabla resumen

| Función | ¿Qué la mueve? | ¿Modelo entrenado? | Dónde corre |
|---|---|---|---|
| Carga sugerida para la próxima sesión | Random Forest propio | **Sí** | Edge Function `sugerir-carga` |
| Estimar calorías desde una foto | Gemini 3.6 Flash (API de Google) | Sí, pero **ajeno** | Edge Function `analizar-comida` |
| Calificación de la sesión (0–100) | Aritmética con pesos fijos | No | SQL + JavaScript |
| Diagnóstico de rutina propia | Árbol de reglas escrito a mano | No | JavaScript en el cliente |
| Mapa muscular y fichas de técnica | SVG generado por código, texto fijo | No | JavaScript en el cliente |
| Plan de calorías del onboarding | Mifflin-St Jeor + fórmula Navy | No | JavaScript en el cliente |

---

### 3.1 Modelo predictivo de carga — **la IA del proyecto**

Es lo único que se puede llamar con propiedad "un modelo entrenado por
nosotros", y es el corazón de H1.

**Qué predice.** El *cambio* de carga (`delta_kg`) para la próxima sesión de un
ejercicio concreto, no la carga absoluta. Predecir el cambio es más fácil de
aprender y hace que el error sea directamente interpretable en kilos.

**Algoritmo.** `RandomForestRegressor` de scikit-learn: 40 árboles, profundidad
máxima 6, mínimo 20 muestras por hoja.

**Variables (51).** 28 numéricas + 6 categóricas en uno-de-N:

- *Del ejercicio y la persona*: `session_no`, `age_years`, `height_cm`,
  `experience_months`, `load_increment_kg`, `sex`, `goal`, `muscle_group`,
  `movement_pattern`, `equipment`, `is_compound`.
- *De la última sesión*: `top_weight_kg`, `avg_reps`, `avg_rir`, `min_rir`,
  `total_volume_kg`, `top_e1rm_kg`.
- *Del historial*: `prev1/2/3_weight_kg`, `prev1/2_avg_rir`, `prev1_volume_kg`,
  `prev1_e1rm_kg`, `days_since_prev_session`, `pct_change_vs_prev`.
- *Del contexto*: `sleep_h_7d`, `bodyweight_7d_kg`.
- *Nutricionales (H2)*: `kcal_7d`, `kcal_target_7d`, `kcal_balance_7d`,
  `protein_7d`, `protein_g_per_kg_7d`, `days_logged_7d`.

Se excluye **a propósito** `days_to_next_session`: solo se conoce después, y
usarla sería fuga de información del futuro.

**Cómo se evalúa.** Partición **temporal** (el último 25 % de cada serie
usuario×ejercicio va a prueba, nunca se entrena con el futuro) y partición por
**usuarios no vistos**. Se compara siempre contra tres líneas base:

| | MAE |
|---|---|
| Persistencia (repetir la misma carga) | 1.768 kg |
| Progresión lineal (+1 disco siempre) | 3.408 kg |
| Lineal doble autorregulada por RIR | 1.782 kg |
| **Modelo (partición temporal)** | **0.902 kg** — 49.0 % mejor |
| Modelo, usuarios nunca vistos | 0.925 kg |

93.7 % de las sugerencias caen dentro de un disco del peso correcto.

> **Advertencia central**: está entrenado **únicamente con datos sintéticos**
> (160 usuarios simulados, 20 semanas, 13 794 filas). No ha visto un solo
> entrenamiento real. Las métricas describen su comportamiento en simulación, no
> su utilidad práctica. Esto está escrito en la propia pantalla de la app, en
> `model_versions.notes` y en el JSON del modelo.

**Cómo llega a producción.** Este es el detalle de arquitectura que más importa
para la versión móvil:

```
ml/generar_datos.py   → datos sintéticos (modelo Banister de fitness-fatiga)
ml/exportar_modelo.py → entrena y exporta v2/modelo.json (88 KB, 3 674 nodos)
ml/evaluador.js       → evalúa el bosque sin Python; sirve para verificar paridad
supabase/functions/sugerir-carga/ → mismo evaluador, en Deno
```

No hay Python en producción. **Un bosque de decisión es una lista de
comparaciones**, así que el modelo se exporta a JSON (para cada nodo: qué
variable mira, con qué umbral compara, a dónde va, y qué valor tiene la hoja) y
se recorre en unas veinte líneas de código. La Edge Function lo descarga una vez
por instancia desde GitHub Pages y lo deja en memoria.

Verificado: sobre 50 vectores de prueba, la diferencia entre lo que calcula
scikit-learn y lo que calcula el JavaScript es de **5×10⁻⁷ kg**.

**Capas de seguridad sobre la salida del modelo.** El modelo propone, pero antes
de mostrar nada:

1. Se redondea al múltiplo del disco disponible (`load_increment_kg`). En el
   gimnasio no existe 63.7 kg.
2. Se recorta: nunca sube más de dos discos ni más del 10 %, nunca baja más del
   20 %. Cuando recorta, se guarda **por qué** (`clamp_reason`), porque una
   recomendación recortada no es lo mismo que una que el modelo dio directamente.

**Cómo se mide el error en la vida real.** La predicción se escribe en la tabla
`predictions` **antes** de que la persona entrene. Después, la función
`close_prediction_loop` rellena `error_kg` comparando contra lo que de verdad
levantó. Sin ese registro previo, "el modelo acierta" sería imposible de
comprobar. La vista `v_error_modelo` lo resume separando siempre lo real de lo
inventado.

**Umbral de arranque**: el modelo necesita **2 sesiones del mismo ejercicio**
para sugerir algo. Se midió: bajar de 3 a 2 no empeora el error (0.902 vs 0.908)
y significa que la persona recibe algo útil en su segunda visita en vez de a las
tres semanas. El umbral viaja dentro del JSON del modelo (`min_sesiones`), no
está escrito en el código de la función.

---

### 3.2 Escáner de comida — IA ajena (Gemini)

Aquí no hay modelo propio: se le pide a un LLM multimodal de Google que estime
las calorías de una fotografía.

- **Modelo**: `gemini-3.6-flash` (configurable con el secreto `GEMINI_MODEL`).
- **Endpoint**: `POST https://generativelanguage.googleapis.com/v1beta/interactions`
  — la Interactions API, que sustituyó a `generateContent`.
- **Dónde corre**: Edge Function `analizar-comida`. La llave de Gemini es un
  secreto del proyecto Supabase. **Nunca sale al navegador**: si estuviera en el
  HTML, cualquiera podría leerla con "ver código fuente" y gastar la cuota.
- **Salida estructurada**: se pide con `response_format` y un esquema JSON fijo
  (alimentos con porción, totales, confianza alta/media/baja, y una nota sobre
  qué es lo más incierto).

**Sobre la privacidad de la foto.** La app promete que la imagen no se guarda, y
esa promesa se cumple en los dos extremos:

- Del lado de Supabase: no se escribe en Storage, ni en una columna, ni en el
  log. Solo persiste la fila numérica en `food_scans`, que no tiene ninguna
  columna capaz de contener una imagen (verificado contra el catálogo de
  Postgres).
- Del lado de Google: la Interactions API **guarda las interacciones por
  defecto** (`store=true`, un día de retención en la capa gratuita). Se manda
  explícitamente `store: false`. Este detalle se pasó por alto en la primera
  versión y se corrigió; conviene no perderlo de vista al portar.

**Detalle de implementación que costó una iteración.** La respuesta de la
Interactions API no es un objeto plano: es una secuencia de pasos de ejecución
(pensamientos del modelo, llamadas a herramientas, salida final) y su forma ha
cambiado entre versiones de la API. En vez de apostar por una ruta concreta, el
código **recorre el árbol completo de la respuesta** buscando el primer objeto
con la forma esperada, y también desenvuelve el JSON si viene entre ` ```json `.
Probado contra ocho envoltorios distintos.

**Un valor estimado por foto no es una medición.** Entra a `nutrition_logs` con
`source = 'photo_ai'`, y las vistas del estudio siguen contando solo
`source = 'manual'`. Cuenta como estimación **aunque la persona corrija las
cifras**, porque el punto de partida sigue siendo lo que dijo el modelo y el
anclaje es real. `food_scans` guarda lo que estimó el modelo y lo que la persona
terminó guardando, así que `v_error_estimador` da el MAE del estimador.

Límite: 25 fotos por persona al día, contado **en el servidor**. Si se contara en
el cliente bastaría con recargar la página para saltárselo.

---

### 3.3 Lo que NO es IA (aunque lo parezca)

**Calificación de la sesión (0–100).** Aritmética pura con cuatro componentes de
peso fijo: esfuerzo dentro de la ventana de RIR del ejercicio (40 %), progresión
del 1RM estimado contra la sesión anterior (25 %), qué tanto del registro se
completó (20 %) y constancia (15 %). La fórmula está duplicada en SQL
(`v_session_score`) y en JavaScript (`calificar()`), con las mismas constantes.
No hay nada estimado: todo sale de peso, repeticiones y RIR.

**Diagnóstico de rutina propia.** Compara el volumen semanal por grupo muscular
contra rangos de prescripción de uso común y señala desequilibrios. Es un árbol
de decisiones escrito a mano. La app lo dice en pantalla: *"el análisis usa
reglas de prescripción de uso común, no el modelo predictivo"*. Hay una
suposición declarada en la interfaz: el volumen se proyecta como
`días ÷ nº de rutinas`.

**Mapa muscular y fichas de técnica.** 29 siluetas SVG generadas por código
(1.24 KB cada una) con el grupo muscular resaltado, más tres puntos de técnica
por ejercicio escritos a mano. Cero IA, cero red, funciona sin conexión.

> Nota histórica: se intentaron diagramas de movimiento tipo figura de palitos y
> **salieron inservibles** — se renderizaron a PNG para verlos y el peso muerto
> era una línea vertical con dos barras. Se descartaron. También se descartó
> generar imágenes de ejercicios con IA: fallan en anatomía. Y se descartó
> explícitamente el análisis de postura por vídeo, por decisión del autor: *"es
> mucho para lo que realmente se busca, que es la progresión de un diario de
> gym, no un entrenador personal"*.

**Plan de calorías del onboarding.** Mifflin-St Jeor para el metabolismo basal,
fórmula Navy para el porcentaje de grasa, Epley para el 1RM estimado
(`peso × (1 + reps/30)`). Fórmulas de libro.

---

## 4. Base de datos

Postgres 17 en Supabase. **20 migraciones**, 15 tablas, 14 vistas.

### Tablas

`profiles` · `exercises` · `routines` · `routine_exercises` · `workouts` ·
`workout_sets` · `body_weights` · `body_measures` · `sleep_logs` ·
`nutrition_logs` · `swims` · `plan_targets` · `model_versions` · `predictions` ·
`food_scans`

Catálogo global: **29 ejercicios**, **8 rutinas** (upperA/B/C, lowerA/B,
fullA/B/C) con series, repeticiones y ventana de RIR objetivo por ejercicio.

### Vistas

`v_ml_dataset` es la importante: entrega exactamente las 51 variables del modelo,
ya calculadas con ventanas móviles de 7 días y desfases (`lag`) por serie
usuario×ejercicio. El generador sintético emite las mismas columnas, así que
entrenar con datos reales no requiere tocar el código de entrenamiento.

Las demás: `v_session_score`, `v_session_score_total`, `v_weekly_score`,
`v_weekly_volume`, `v_personal_records`, `v_body_fat`, `v_working_sets`,
`v_exercise_sessions`, `v_error_modelo`, `v_error_estimador`, y tres de
administración (`v_admin_participantes`, `v_admin_progreso`, `v_admin_ejercicios`).

### Seguridad

- **RLS en todas las tablas de usuario.** Verificada bajo un JWT real
  (`set local role authenticated` + `request.jwt.claims`), no asumida.
- El investigador tiene lectura sobre todos, escritura sobre nadie.
- `private.es_admin()` vive en un esquema privado para que PostgREST no la
  publique como endpoint RPC.
- Todas las vistas con `security_invoker = on`.
- 0 avisos del linter de seguridad de Supabase, salvo uno de configuración de
  Auth (protección contra contraseñas filtradas, pendiente de activar).

### Sincronización sin conexión

El punto delicado de toda la app. Cada registro lleva un `client_uid` generado en
el dispositivo, con restricción `unique (user_id, client_uid)`, y la subida es
idempotente por `upsert`.

**Cuatro errores encadenados destruyeron datos reales de entrenamiento** una vez.
Vale la pena conocerlos porque cualquier cliente nuevo puede repetirlos:

1. La descarga no filtraba por usuario. El investigador tiene permiso de lectura
   sobre todos: su app se bajaba los datos de todo el mundo y luego los volvía a
   subir como propios.
2. Cerrar sesión no limpiaba el almacenamiento local.
3. Los datos locales no llevaban marca de a qué cuenta pertenecían (`cfg.owner`).
4. La subida hacía `delete` de las series y luego `insert`. Si la traducción
   fallaba, borraba sin poder reponer.

Arreglos: filtrar siempre por `user_id`, sellar los datos con su dueño, preguntar
antes de adoptar datos huérfanos, y **construir las filas antes de borrar nada**
— si no hay nada que subir, no se toca el servidor.

También hay autoguardado de borrador (`gymDiary_borrador_v2`): perder una sesión
a medio capturar era una fuente real de datos perdidos.

---

## 5. Pruebas

**385 pruebas** en 12 suites, todas pasando. Corren con jsdom sobre el HTML real,
no sobre mocks del código.

| Suite | Qué cubre | n |
|---|---|---|
| `test_app` | Núcleo, cálculos, render | 38 |
| `test_onboarding` | Los 6 pasos y el plan generado | 42 |
| `test_panel` | Panel del investigador, modo feria | 39 |
| `test_borrador` | Autoguardado y recuperación | 43 |
| `test_pass` | Ver contraseña y recuperación | 26 |
| `test_rutinas_sync` | Rutinas propias → Supabase | 15 |
| `test_cuentas` | Los cuatro errores de sincronización | 18 |
| `test_calificacion` | Fórmula de puntuación | 26 |
| `test_diagramas` | Mapa muscular, 29 ejercicios | 23 |
| `test_version` | Service worker y actualización forzada | 21 |
| `test_comida` | Escáner, privacidad, XSS | 50 |
| `test_sugerencia` | Modelo, paridad con Python, interfaz | 41 |

Detalle útil para quien las lea: en jsdom, `let` y `const` de nivel superior
**no** quedan en `window`; las declaraciones `function` sí. Varias pruebas
comprueban el código fuente con expresiones regulares por esa razón.

---

## 6. Lo que falta

1. **Participantes reales.** Es el cuello de botella de todo. La confirmación de
   correo bloqueó el reclutamiento durante semanas; ya está desactivada.
2. **Reentrenar con datos reales.** Hoy el modelo solo ha visto simulación.
3. **Arranque en frío.** Un usuario nuevo no tiene historial. La idea pendiente
   es un modelo entrenado con OpenPowerlifting para el primer día.
4. **Volver a medir H2** cuando haya datos reales.
5. Limpieza menor del repositorio: `index.html.bak` y `ml/__pycache__/` no
   deberían estar versionados.

---

## 7. Para la versión móvil (Android e iOS)

### Qué se conserva tal cual

Todo el backend. La base de datos, las políticas de RLS, las dos Edge Functions,
el modelo exportado y el catálogo de ejercicios son independientes del cliente.
Una app nativa consume exactamente lo mismo.

- `supabase-js` tiene equivalentes oficiales para Flutter (`supabase_flutter`) y
  para React Native.
- Las Edge Functions se invocan igual (`functions.invoke`).
- **La lógica de negocio que hay que portar con cuidado** está toda en
  `v2/index.html`: la fórmula de calificación, el generador de plan, el
  diagnóstico de rutinas, el mapa muscular y —sobre todo— la máquina de
  sincronización.

### Qué hay que rehacer

El cliente entero. `v2/index.html` son 152 KB de HTML, CSS y JavaScript en un
solo archivo, sin compilación ni componentes. Fue la decisión correcta para
llegar rápido a algo usable, y es exactamente lo que no se puede portar: hay que
reescribir la interfaz en el marco que se elija.

### Decisiones abiertas para el nuevo chat

1. **Marco**: Flutter, React Native o dos apps nativas. Flutter y RN comparten
   código entre las dos plataformas; nativo da mejor integración con Salud/Fit.
2. **¿Dónde corre el modelo en móvil?** Ahora mismo la inferencia es un viaje al
   servidor. En una app nativa el mismo JSON de 88 KB se puede evaluar **en el
   dispositivo**, y el evaluador son veinte líneas — funcionaría sin conexión.
   Pero entonces hay que resolver cómo se siguen registrando las predicciones en
   `predictions`, porque sin ese registro se pierde la capacidad de medir el
   error, que es el sustento del estudio.
3. **Cámara y foto de comida.** En móvil el flujo mejora mucho (cámara nativa,
   sin selector de archivos). La promesa de que la foto no se guarda hay que
   sostenerla también en el dispositivo: no dejarla en la galería ni en caché.
4. **Sincronización sin conexión.** Es lo más delicado del proyecto y ya costó
   datos reales una vez. Conviene portar el diseño (`client_uid`, sello de
   dueño, construir antes de borrar) en vez de improvisar uno nuevo.
5. **Notificaciones.** No existen hoy. Serían la palanca más directa para que los
   participantes registren a diario, que es de lo que depende el estudio entero.
6. **Salud/Fit.** Peso y sueño podrían leerse de Apple Health o Health Connect en
   vez de capturarse a mano. Ojo: eso cambia el `source` del dato y hay que
   distinguirlo de lo capturado por la persona, igual que se hizo con `photo_ai`.

### Archivos que conviene leer primero

```
v2/index.html                        el cliente entero (la lógica a portar)
v2/panel.html                        panel del investigador
v2/modelo.json                       el bosque exportado
supabase/migrations/*.sql            20 migraciones, en orden, comentadas
supabase/functions/sugerir-carga/    inferencia
supabase/functions/analizar-comida/  escáner de comida
ml/exportar_modelo.py                entrenamiento y exportación
ml/evaluador.js                      el evaluador de referencia
ml/README.md                         metodología y resultados
docs/ESQUEMA.md                      diccionario de datos
supabase/README.md                   operaciones y despliegue
```

---

## 8. Principios que conviene mantener

Estos no son adornos: cada uno salió de un error concreto.

- **Distinguir siempre lo medido de lo estimado.** `source` en `nutrition_logs`,
  `is_demo` en `profiles`, `clamped` en `predictions`. Si se mezclan, los
  resultados dejan de significar nada.
- **Registrar la predicción antes de conocer el resultado.** Es la diferencia
  entre poder reportar un error y solo afirmar que el modelo funciona.
- **Comparar siempre contra líneas base tontas.** Un MAE de 0.9 kg no dice nada
  hasta que se sabe que repetir la misma carga da 1.77 kg.
- **Los límites de uso y de seguridad se cuentan en el servidor.** Lo que vive en
  el cliente se salta recargando la página.
- **Decir en la pantalla lo que el sistema no sabe.** La app dice que el modelo
  solo ha visto datos sintéticos, que la estimación por foto se equivoca fácil, y
  que el diagnóstico de rutinas son reglas y no un modelo. Eso no resta: es lo
  que hace defendible el proyecto ante un revisor.
