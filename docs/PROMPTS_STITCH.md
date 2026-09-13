# Prompts para Stitch — GymAI

Se pegan **en orden**. El primero establece el sistema de diseño; los demás son una
pantalla cada uno. Stitch trabaja mejor con una pantalla por petición que con un
"diseña toda la app".

Antes de nada, lee la sección final: **hay cosas que no se pueden rediseñar**, y si
las quitas el proyecto pierde justo lo que lo hace defendible.

---

## 0 · Sistema de diseño (pegar primero)

```
Design a mobile app called GymAI, a strength-training diary that doubles as a
research instrument. Spanish (Mexico) UI. Dark theme only.

COLOR TOKENS — use these exact hex values, do not substitute:
  Background        #0f1c19
  Card surface      #162622
  Raised surface    #1c2f2a
  Borders/dividers  #2a423b
  Primary text      #e8f0ed
  Secondary text    #8fa8a0
  Accent (green)    #4ecfa8
  Accent deep       #2f6a5e
  Warning (amber)   #e8a33d
  Danger (red)      #e2674f

TYPOGRAPHY: system sans-serif (SF Pro / Roboto). Base 16px, line-height 1.5.
Section titles 17px semibold. Metric labels 10-11px uppercase with 0.6px letter
spacing, in secondary text color. Big numbers 28-34px in accent green.

LAYOUT LANGUAGE:
- Cards with 14px radius, 1px border in #2a423b, no drop shadows.
- Generous vertical rhythm: 14px inside cards, 16px between cards.
- Inputs 12px padding, 8px radius, 16px font so iOS doesn't zoom on focus.
- Pills/chips: 99px radius, 11px semibold, tinted background at 15% opacity of
  their color (green = good, amber = warning, red = problem, grey = no data).
- Horizontal scrolling tab bar at the top, not a bottom nav. Active tab is a
  filled green pill; inactive tabs are text in secondary color.
- Charts are minimal line charts: 1px grid lines in #2a423b, 2.5px stroke in
  accent green, small filled dots on data points, dashed grey line for targets.

TONE: calm, dense with information, gym-notebook rather than fitness-influencer.
No gradients, no glass morphism, no neon glow, no 3D illustrations, no stock
photos of people working out. Data first.

ACCESSIBILITY: this is used one-handed, mid-set, with sweaty hands, often in bad
gym lighting. Tap targets at least 44px. Numeric inputs large and far apart.
Contrast must hold at low screen brightness.

Confirm you have the tokens, then wait for the screen descriptions.
```

---

## 1 · Panel (pantalla de inicio)

```
Screen 1 of 7: "Panel" — the home dashboard.

Header: app icon, title "Diario de Entrenamiento", subtitle line
"2330774 · Recomposición · 26 semanas", then "Semana 4 de 26 · Fase 2 · 2,150 kcal",
then a small sync status row with a green dot: "Sincronizado 19:33".

Tab bar: Panel · Pesas · Peso y medidas · Comida · Natación · Progreso · Datos

Content, in cards, top to bottom:

1. A 2x2 grid of KPI tiles. Each: tiny uppercase label, big green number, small
   delta line underneath in secondary color.
   - "Promedio 7 días" → 72.6 kg → "−0.42 kg vs. semana pasada"
   - "Objetivo esta semana" → 71.8 kg → "vas 0.8 kg arriba"
   - "Cintura" → 92.0 cm → "−1.5 cm desde el inicio"
   - "Grasa estimada" → 21.4 % → "±4 puntos de error"

2. Card "Calificación del entrenamiento": a large 0-100 number (84) with a green
   "Buena" chip beside it, then FOUR horizontal progress bars stacked, each
   labelled with its weight: Esfuerzo 40, Progresión 25, Registro 20,
   Constancia 15. Filled portion in accent green, track in #2a423b.
   Below, a small weekly trend line chart.

3. Card "Registro rápido de hoy": date field, weight field, sleep hours field,
   and a full-width green "Guardar" button.

4. Card "Últimas sesiones": a compact list. Each row = date, routine name,
   number of sets, and a small score chip on the right.

Make the four component bars of the score visually more important than the
single number — the breakdown is what the user acts on.
```

---

## 2 · Pesas (registrar sesión)

```
Screen 2 of 7: "Pesas" — logging a training session. The most used screen.

Card "Carga sugerida": explanatory subtitle, an outline button
"Calcular sugerencia", and results as a 3-column table:
Ejercicio | Última | Sugerido. The suggested value is green with an arrow
(↑ 62.5 kg). One row shows a small caption "ajustada al límite de seguridad".
A footnote states the model's error and that it was trained on simulated data.

Card "Registrar sesión": date picker and routine dropdown side by side, then a
list of exercise blocks. Each exercise block:
  - Header row: exercise name in bold on the left; on the right the target
    "4 × 8 · RIR 1-3" plus a small outline pill button "ver".
  - When "ver" is expanded: a muscle-map silhouette SVG on the left (about
    130px wide, muscle worked highlighted in accent green, rest of the body in
    muted #3c574f) and three technique bullets on the right.
  - A "Última vez (13 ago): 60kg × 8 @2 · 60kg × 8 @1" line in secondary color.
  - A green line "El modelo sugiere 62.5 kg (+2.5)" with a small "usar" pill.
  - Then the set rows: a 5-column grid — set number, KG input, REPS input,
    RIR input, delete ✕. Column headers above in tiny uppercase.
  - "+ Serie" ghost button at the bottom of the block.

CRITICAL: the RIR input must be visually distinct from KG and REPS — give it a
faint green tint background and a green-tinted border. It is the single most
important field in the whole app and the one people skip. Below the exercise
list there is a note explaining what RIR is; keep it, do not shorten it to an
icon or a tooltip.

Bottom of the card: session RPE and duration fields, a notes field, and a
full-width "Guardar sesión" button.
```

---

## 3 · Comida

```
Screen 3 of 7: "Comida" — nutrition.

Card "Tu plan de alimentación": a table of food-equivalent groups. Columns:
Grupo | Des. | Com. | Cena | Día. Each row has the group name in primary text
and, underneath in small secondary text, example portions
("1 tortilla · ½ bolillo · ½ taza de arroz cocido").
Below the table, a 4-metric summary row (Kcal, Proteína, Carbohidratos, Grasa)
with big green numbers, then an outline button "Sugerir platillos con IA".

Card "Desayuno, comida y cena": a date field, then three collapsible meal
blocks. Each block header: meal name on the left, total kcal in green on the
right. Inside: a list of logged entries — description, kcal, and a chip that
says either "a mano" (green) or "foto" (amber) — plus a ✕ to remove. Two ghost
buttons at the bottom of each block: "Foto" and "A mano".

Below the three blocks, a summary panel: total kcal and macros, a green button
"Sumar al registro del día", and a caption stating what percentage of those
calories came from photos.

Camera result state (design this as a variation): a small square photo preview
on the left, and on the right a card listing detected foods with their portions
and kcal, a confidence chip ("confianza media" in amber), the model's note about
what is uncertain, and two buttons: "Añadir a Cena" and "Descartar".

The line "La foto no se guarda" must stay visible and legible — it is a promise
to research participants, not fine print.
```

---

## 4 · Progreso

```
Screen 4 of 7: "Progreso" — charts.

Four chart cards, each with a title, a one-line explanation in secondary text,
and a minimal line chart. X axis is plan weeks labelled S1, S2, S3…

1. "Peso: real vs. objetivo" — two lines: solid accent green (actual weekly
   average) and dashed grey (plan target). Legend below.
2. "Cintura: real vs. objetivo" — same treatment.
3. "Volumen semanal de pesas" — single green line, y axis in tonnes.
4. "Ritmo de natación" — single green line, y axis in seconds per 100 m.
   IMPORTANT: on this chart lower is better. Make that unmistakable in the
   layout — the caption says "hacia abajo es mejor" and it must not get lost.
   Under the chart, a summary line: "De 1:50 a 1:36 por 100 m en 6 series ·
   14 s más rápido · 12.4 km nadados en total".

Charts must read at a glance in daylight: 2.5px strokes, visible dots, axis
labels no smaller than 11px.
```

---

## 5 · Cuestionario inicial (onboarding)

```
Screen 5 of 7: a 6-step onboarding questionnaire, one question per screen,
full-bleed, with a progress bar of 6 segments at the top and a small
"Paso 4 de 6" label.

Design step 4: "¿Cuántos días puedes entrenar?"
- Lead paragraph in secondary text: "Sé realista: más vale sostener tres días
  ocho semanas que abandonar cinco a la tercera."
- Four large selectable cards stacked vertically: 3 días / 4 días / 5 días /
  6 días. Each card has a bold title and a one-line description. Selected card
  has an accent green border and a subtle green tint.
- Below: a dropdown "¿Qué quieres priorizar?" with options Equilibrado, Más
  tren superior, Más tren inferior — and directly under it a small caption:
  "Esto no depende de tu sexo: depende de lo que quieras entrenar."
- Then a dropdown "¿Cuánto llevas entrenando con pesas?"
- Footer: ghost "Atrás" and filled green "Continuar".

Also design step 6, the plan summary: a two-column table of results (Objetivo,
Duración, Peso, Calorías al inicio, Proteína al día, Entrenamiento, Énfasis,
Rutinas), then a distinct consent card with a checkbox and a paragraph about
anonymised research use, then a green "Empezar" button. The consent card must
look like something you read, not like a cookie banner you dismiss.
```

---

## 6 · Panel del investigador (web, no móvil)

```
Screen 6 of 7: a desktop/tablet research dashboard, same dark palette.

Top bar: title "Panel del investigador", a toggle labelled
"Modo feria (oculta nombres)", and two tabs: Seguimiento · Presentación.

A banner across the top when demo data is present: amber-tinted, stating that
some participants are fabricated for demonstration.

Cards:
1. "Alertas" — a stack of alert rows. Amber for warnings, red border for
   serious ones. Example texts: "P03 lleva 12 días sin registrar una sesión",
   "P02 registra el 30 % de sus series con RIR".
2. "Participantes" — a dense table: Participante, Objetivo, Días/sem, Sesiones,
   Sin entrenar, % RIR, Pesos, Comidas, Consiente. The "Sin entrenar" and
   "% RIR" cells are chips, colour-coded. Some rows carry a small "demo" chip.
3. "Natación" — a table with Sesiones, Km, Sin nadar, Ritmo inicial, Ritmo
   actual, Cambio. The change cell is a chip: green when negative (faster).
4. "El modelo predictivo" — a comparison table of the model against three
   baseline rules, with the model's row highlighted.

Dense and scannable. This is an instrument panel, not a marketing page.
```

---

## 7 · Estados vacíos y de error

```
Screen 7 of 7: empty and error states, as a set of small cards.

1. No sessions yet: "Todavía no hay entrenamientos registrados."
2. Model has no history for an exercise: "El modelo necesita al menos dos
   sesiones del mismo ejercicio para tener con qué comparar."
3. Scanner unavailable: "El escáner no está configurado todavía."
4. Offline: the sync dot turns grey and reads "Modo local · sin conexión".
5. A loading state: a small spinning ring next to button text ("Analizando…").

Keep every message a full sentence that says what happened and what to do.
No sad-face illustrations, no "Oops!", no empty-state mascots.
```

---

## Lo que NO se puede rediseñar

Si Stitch propone quitar cualquiera de estas cosas porque "ensucian" la interfaz,
se rechaza. Cada una está ahí por una razón concreta y sin ellas el proyecto deja
de ser defendible ante un revisor.

| Elemento | Por qué se queda |
|---|---|
| Campo **RIR** destacado en cada serie | Sin él no se puede saber si la carga fue la correcta, y el dato no se recupera después |
| Chip **"foto" / "a mano"** en cada comida | Distingue un dato medido de uno estimado por un modelo |
| **"La foto no se guarda"** | Es una promesa a los participantes, no letra chica |
| Aviso de **datos de demostración** | Impide que alguien confunda una demo con evidencia |
| **"todavía no ha visto entrenamientos reales"** en la carga sugerida | Es la advertencia que sostiene la honestidad del proyecto |
| Nota de que el diagnóstico de rutinas **son reglas, no el modelo** | No todo lo de la app es IA y hay que decirlo |
| **"hacia abajo es mejor"** en la gráfica de natación | Es la única gráfica invertida; sin el aviso se lee al revés |
| Casilla de **consentimiento** con su párrafo completo | Requisito ético del estudio |

## Cómo usar el resultado

Stitch entrega HTML/CSS o Figma. **No lo pegues encima de `v2/index.html`.** La app
es un solo archivo con la lógica y los estilos entrelazados, y sobrescribirlo se
llevaría la sincronización, el modelo y las 514 pruebas por delante.

El camino seguro: tomar de Stitch **solo el bloque `<style>`** y los fragmentos de
marcado de las tarjetas nuevas, e irlos aplicando pantalla por pantalla,
corriendo la suite entre cada una. Varias pruebas verifican textos e
identificadores concretos (`cmFoto-desayuno`, `verdiag`, `chNado`,
`cfgProgTxt`…): si Stitch los renombra, las pruebas lo van a marcar, que es
exactamente para lo que están.
