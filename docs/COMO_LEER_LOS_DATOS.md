# Cómo leer los datos de GymAI

Guía de interpretación: qué mide cada número, cómo se calcula exactamente, qué
significa que suba o baje, y en qué se equivoca la gente al leerlo.

Está escrita para que puedas defender cualquier gráfica de la app y del panel sin
tener que abrir el código.

---

## Tres reglas antes de mirar cualquier número

**1. Un dato medido y un dato estimado no son lo mismo.**
La app lo marca en todos lados: `source` en la comida, `is_demo` en los
participantes, `clamped` en las predicciones. Cuando presentes un número, di
siempre de cuál de los dos está hecho. Si mezclas los dos, el número deja de
significar algo.

**2. La tendencia importa; el punto suelto no.**
El peso corporal se mueve ±1 kg al día por agua, sal y contenido intestinal. Una
sola medición no dice nada. Por eso casi todo en la app está promediado.

**3. Un número sin comparación no se puede juzgar.**
"El error del modelo es 0.9 kg" no significa nada hasta que sabes que repetir la
misma carga da 1.77 kg. Siempre lleva la referencia contigo.

---

## Peso y composición corporal

### Promedio de 7 días

**Cómo se calcula.** El promedio de tus últimos 7 registros de peso. Al lado se
muestra la diferencia contra el promedio de los 7 anteriores.

**Cómo se lee.** Solo la diferencia entre los dos promedios cuenta como cambio
real. Si bajaste 0.4 kg de un promedio al otro, bajaste 0.4 kg; que ayer la
báscula marcara 800 g menos que anteayer no es información.

**Qué es rápido y qué es lento.** Una pérdida sostenible va de 0.5 a 1 % del peso
corporal por semana. En 73 kg eso son 350 a 730 g. Más rápido y una parte de lo
que se va es músculo.

> ⚠ **Detalle honesto:** el promedio de la app es de los últimos 7 **registros**,
> no de los últimos 7 **días**. Si te pesas cuatro veces por semana, esa cifra
> cubre unos 12 días, no 7. En la base de datos —que es lo que usa el modelo— sí
> es una ventana de calendario real (`between performed_on - 7 and performed_on`).
> Para uso personal da casi igual; si lo vas a citar en el artículo, cita el de la
> base. Se puede igualar en la app, es un cambio pequeño.

### Gráfica «Peso: real vs. objetivo»

**Eje X:** semanas del plan, contadas desde `plan_start`. **Eje Y:** kilos.
La **línea punteada gris** es la curva que el plan proyecta; la **línea verde** es
tu promedio semanal real.

**Cómo se lee.** No importa que la verde esté por encima o por debajo de la gris:
importa que sean **paralelas**. Paralelas = estás bajando (o subiendo) al ritmo
planeado, aunque partieras de otro punto. Si la verde se aplana y la gris sigue
cayendo, el déficit dejó de existir y hay que ajustar calorías.

**El error clásico.** Ver que la verde está por encima de la gris y concluir "voy
mal". Puede que solo hayas empezado más pesado. Mira la pendiente, no la
distancia.

### Cintura

Es la mejor señal de grasa abdominal disponible sin equipo. Se mide de pie,
relajado, sin meter la panza, al exhalar normal.

**Por qué importa más que el peso.** En recomposición el peso puede no moverse
durante semanas mientras la cintura baja. Eso es exactamente lo que buscas:
perdiste grasa y ganaste músculo al mismo tiempo. Si solo miraras la báscula
concluirías que no pasa nada.

### Grasa estimada (fórmula Navy)

**Cómo se calcula.** A partir de cintura, cuello y estatura:

```
densidad = 1.0324 − 0.19077 × log₁₀(cintura − cuello) + 0.15456 × log₁₀(estatura)
% grasa  = 495 / densidad − 450
```

**Cómo se lee.** Con un margen de error de **±3 a 4 puntos porcentuales**. Si te
dice 22 %, la verdad está entre 18 y 26. Sirve para ver si el número **baja con el
tiempo**, no como valor absoluto. Nunca lo presentes como una medición: es una
estimación de una fórmula de 1984 hecha para la marina estadounidense.

---

## Pesas

### 1RM estimado (fórmula de Epley)

```
1RM ≈ peso × (1 + repeticiones / 30)
```

**Qué es.** Cuánto podrías levantar una sola vez, estimado a partir de una serie
de varias repeticiones. Permite comparar sesiones distintas: 60 kg × 8 y 70 kg × 5
no se pueden comparar directamente, pero sus 1RM estimados sí (76 kg contra 81.7).

**Dónde falla.** La fórmula es fiable hasta unas 10 repeticiones. Por encima de
eso infla el resultado: 40 kg × 20 da un 1RM de 66.7 kg que casi nadie levantaría.
En ejercicios de aislamiento con muchas repeticiones —elevaciones laterales,
pantorrilla— trátalo como un índice de progreso, no como un peso real.

### Volumen semanal (toneladas)

```
volumen = Σ (peso × repeticiones) de todas las series de la semana
```

**Cómo se lee.** Es tu capacidad de trabajo. Suele subir en las semanas de carga y
bajar en las de descarga, y eso es normal y deseable. Lo preocupante es una caída
sostenida de tres o más semanas sin haberla planeado: significa que estás
acumulando fatiga o comiendo demasiado poco.

**El error clásico.** Perseguir más tonelaje. Se sube fácil haciendo más series
malas. El volumen acompaña, no manda.

### Calificación de la sesión (0 a 100)

Cuatro componentes con peso fijo. Todo sale de peso, repeticiones y RIR: no hay
nada estimado ni ningún modelo detrás.

| Componente | Peso | Cómo se calcula | Qué castiga |
|---|---:|---|---|
| **Esfuerzo** | 40 | Proporción de series cuyo RIR cayó dentro de la ventana objetivo del ejercicio | Entrenar demasiado suave o llegar al fallo cuando no tocaba |
| **Progresión** | 25 | 1RM medio de la sesión contra el de la sesión anterior del mismo tipo | Estancarse o retroceder |
| **Registro** | 20 | Proporción de series con RIR capturado | Anotar peso y repeticiones pero no el esfuerzo |
| **Constancia** | 15 | Días transcurridos desde la sesión anterior, contra tu frecuencia declarada | Faltar |

Los factores de progresión son escalonados: **1.00** si subiste 2 % o más, **0.85**
si sostuviste, **0.60** si bajaste poco, **0.30** si bajaste mucho, y **0.70** en la
primera sesión, cuando no hay con qué comparar.

**Cómo se lee.** Un 85 con el esfuerzo bajo y el registro alto no es lo mismo que
un 85 con el esfuerzo alto y el registro a medias. **Mira las cuatro barras, no el
número.** El número es un resumen; las barras dicen qué arreglar.

**Por qué el registro pesa 20.** Porque una serie sin RIR no se puede recuperar
después. Es el único componente que mide si estás alimentando el estudio.

---

## Comida

| Indicador | Cómo se calcula | Cómo se lee |
|---|---|---|
| **Kcal promedio 7 días** | Media de los últimos 7 registros con dato | Compara contra el objetivo del plan, no contra un ideal |
| **Balance vs. objetivo** | Promedio real − objetivo del plan | Negativo = déficit. −300 a −500 es un déficit razonable |
| **Proteína por kg** | Proteína promedio ÷ peso corporal | Mínimo 1.8 g/kg en déficit. Por debajo se pierde músculo |
| **Días registrados** | Cuántos de los últimos 7 tienen dato | Menos de 4 y el promedio no es fiable |

### Origen del dato: la columna que decide si un día cuenta

Cada comida guarda si la capturaste tú (`manual`) o la estimó el modelo desde una
foto (`photo_ai`). El día guarda **la proporción exacta** en `pct_estimado`, y su
`source` es `manual`, `photo_ai` o `mixto`.

**Cómo se lee.** Para el estudio, un día con `pct_estimado = 0` es evidencia. Uno
con 100 es una estimación. Uno con 56 es lo que es, y tú decides al analizar dónde
poner el corte —por ejemplo, "solo días con menos del 20 % estimado". Esa decisión
se toma en el análisis, no está congelada en la app.

**Por qué importa tanto.** La hipótesis H2 dice que la nutrición ayuda a predecir
la carga. Si esa hipótesis se prueba con días que un modelo adivinó a partir de
una foto, no se está probando nada.

---

## Natación

**El marcador es el ritmo por 100 m en series de intervalos**, en segundos.

```
ritmo = tiempo total ÷ (metros / 100)
```

**Cómo se lee.** **Hacia abajo es mejor**: menos segundos por cada 100 m es más
rápido. Es lo contrario a casi todas las demás gráficas de la app, y es la
confusión más fácil de cometer al presentarla.

**Por qué solo intervalos.** Un nado continuo suave y una serie de intervalos no
son comparables: el continuo siempre saldrá más lento porque no se está intentando
ir rápido. Si se mezclaran, la curva subiría y bajaría según el tipo de sesión y
parecería que la condición va y viene. Los continuos y los de técnica sí cuentan
para los kilómetros totales.

**Por qué es un buen marcador.** Es la métrica más limpia que hay en toda la app:
si en el mes 3 nadas los mismos 100 m cuatro segundos más rápido con el mismo
descanso, mejoraste. No depende de la báscula ni de estimaciones.

---

## El modelo predictivo

### Las métricas

| Métrica | Qué es | Valor actual |
|---|---|---|
| **MAE** | Error absoluto medio, en kg. Cuánto se equivoca en promedio | **0.902 kg** |
| **RMSE** | Como el MAE pero castiga más los errores grandes | 1.914 kg |
| **± 1 disco** | Proporción de veces que acierta dentro del disco más chico | 93.7 % |
| **MAE en usuarios nuevos** | El mismo error con personas que nunca vio | 0.925 kg |

**Cómo se leen juntos.** Si el RMSE es mucho mayor que el MAE, hay pocos errores
muy grandes escondidos entre muchos aciertos. Aquí lo es (1.9 contra 0.9), y tiene
sentido: la mayoría de las veces la carga no cambia y el modelo acierta exacto,
pero cuando alguien da un salto grande se lo pierde.

Que el error con **usuarios nuevos** apenas suba (0.925 contra 0.902) es lo que
demuestra que el modelo aprendió un patrón y no memorizó personas. Es la cifra más
importante para defender que sirve.

### Contra qué se compara

| Regla | MAE |
|---|---|
| Repetir la misma carga | 1.768 kg |
| Subir un disco siempre | 3.408 kg |
| Subir o bajar según el RIR | 1.782 kg |
| **El modelo** | **0.902 kg** — 49 % mejor |

La tercera es la que importa: es lo que haría un buen entrenador, autorregulando
por el esfuerzo. Ganarle a esa es el resultado.

**El error clásico.** Presumir el 49 % contra "subir un disco siempre", que es una
regla obviamente mala. Compara siempre contra la mejor.

### `clamped`: cuando el modelo se pasa

Antes de enseñar una sugerencia se aplican dos capas: redondeo al disco disponible
y topes de seguridad (nunca +10 % ni dos discos arriba, nunca −20 %). Cuando el
tope actúa, la fila queda marcada con `clamped = true` y la razón.

**Cómo se lee.** Un porcentaje alto de recortes significa que el modelo está
proponiendo saltos poco realistas y que la seguridad la está poniendo la regla, no
el aprendizaje. En el conjunto de validación va en torno al **15 %**. En producción
todavía no hay ninguna predicción registrada, así que ese dato aún no existe con
datos reales.

### `v_error_modelo`: la única métrica que valdrá de verdad

Todas las cifras de arriba salen de datos simulados. La tabla `predictions` guarda
cada sugerencia **antes** de que la persona entrene, y `close_prediction_loop`
rellena el error después con lo que realmente levantó.

Cuando haya participantes, esa vista dará el MAE real, separado entre
participantes reales y de demostración. **Ese** número es el del artículo.

---

## El panel del investigador

### Tabla de participantes

| Columna | Qué mide | Cuándo preocuparse |
|---|---|---|
| Sesiones | Entrenamientos registrados | — |
| Sin entrenar | Días desde el último registro | **Ámbar a los 7, rojo a los 14** |
| % RIR | Proporción de series con esfuerzo capturado | **Ámbar bajo 50, rojo bajo 20** |
| Pesos | Días con peso corporal | Menos de 3 por semana |
| Comidas | Días con ingesta capturada a mano | Menos de 4 por semana |
| Consiente | Autorizó el uso de sus datos | Sin esto, queda fuera |

**El % de RIR es la columna crítica.** Alguien puede registrar sesiones
perfectamente y aun así ser inútil para el estudio si no captura el esfuerzo: sin
RIR, sus series no entran al modelo y ese dato **no se puede recuperar después**.
Cuando esa columna se pone ámbar, hay que escribirle esa semana, no al mes.

### Alertas

Se generan solas: 7 días sin entrenar, menos del 50 % de RIR, cuenta creada sin
completar el cuestionario, y alta sin consentimiento. Están diseñadas para que no
tengas que revisar la tabla todos los días.

### Modo feria

Sustituye los nombres por códigos (P01, P02…). Actívalo antes de enseñar el panel
a nadie que no seas tú: los participantes consintieron que sus datos anonimizados
se usen en el estudio, no que su nombre aparezca en una pantalla.

### Aviso de datos de demostración

Los 5 participantes inventados llevan la marca `is_demo` **en la base de datos**,
no en el cliente, y el panel lo muestra en pantalla. Nadie tiene que acordarse de
aclararlo. Caducan solos a los 30 días.

---

## Cinco lecturas equivocadas que conviene evitar

1. **Leer la báscula día a día.** Solo el promedio contra el promedio anterior.
2. **Ver la gráfica de peso y comparar alturas en vez de pendientes.** Lo que dice
   si el plan funciona es que las dos líneas sean paralelas.
3. **Leer la gráfica de natación al revés.** Hacia abajo es mejor.
4. **Tomar el % de grasa como una medición.** Es una estimación con ±4 puntos de
   error; solo su tendencia significa algo.
5. **Presentar el MAE del modelo sin la línea base.** 0.9 kg no es bueno ni malo
   hasta que se dice que la alternativa razonable da 1.77.

---

## Si te preguntan en la feria

Tres frases que resuelven la mayoría de las preguntas:

> **«¿Cómo sabes que el modelo funciona?»**
> Comparándolo contra lo que haría un entrenador: repetir la carga o ajustarla por
> el esfuerzo. Esas reglas se equivocan 1.77 kg en promedio; el modelo, 0.9. Y con
> personas que nunca vio se sostiene en 0.93, así que no está memorizando.

> **«¿Con qué datos lo entrenaste?»**
> Con datos simulados de 160 personas, generados con un modelo de fitness-fatiga.
> Todavía no ha visto un entrenamiento real, y eso está escrito en la propia app.
> La tubería ya está lista para reentrenarlo en cuanto haya participantes.

> **«¿Y lo de las fotos de comida?»**
> Eso no es un modelo mío, es Gemini. La foto no se guarda en ningún lado, ni de mi
> lado ni del de Google. Y lo que estima entra marcado como estimación, separado de
> lo que la persona capturó, porque una cosa es un dato y otra una suposición.
