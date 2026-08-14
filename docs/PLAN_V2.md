# GymAI v2 · Plan técnico

Documento de decisión, no de especificación. Recoge lo que pidió el profesor, qué es
viable, qué cuesta y qué riesgos tiene cada parte.

---

## 1. Separación de versiones

Ya está creado el segundo proyecto de Supabase. Las dos versiones no comparten base:

| | v1 · estudio | v2 · desarrollo |
|---|---|---|
| Estado | **Congelada**, en uso | En construcción |
| URL | `/diario-gym/` | `/diario-gym/v2/` |
| Proyecto Supabase | `gymai` · `ckvogrrzhdfdubqcwayn` | `gymai-v2` · `usaosgtherqnqwjhgbtt` |
| Datos | Tus 318 series reales | Vacío, desechable |

La v1 sigue viva y recolectando mientras la v2 se rompe cuantas veces haga falta. Esa
separación es el punto: no se experimenta sobre los datos que estás juntando.

```bash
cd ~/GYM/diario-gym

# Referencia inmutable del punto actual
git tag -a v1.0-estudio -m "Version del estudio: alta, RIR, panel, rutina propia"
git push origin v1.0-estudio

# La v2 vive en una subcarpeta; ambas se publican desde main
mkdir -p v2
cp index.html manifest.json sw.js icon-*.png hero.jpg v2/
```

Los archivos de la raíz **no se vuelven a tocar** hasta que la v2 esté lista. Si hay que
corregir un error de la v1, se corrige ahí y se copia a `v2/`, nunca al revés.

---

## 2. Lo que pidió el profesor

### 2.1 Calificación del entrenamiento · **viable sin nada externo**

Es la única de las cuatro que no necesita ningún modelo de pago, y es la más defendible
académicamente porque se calcula con los datos que ya recolectas.

Calificación por sesión (0-100), compuesta por:

| Componente | Peso | De dónde sale |
|---|---:|---|
| Esfuerzo en la ventana objetivo | 40 % | ¿El RIR cayó entre `target_rir_min` y `target_rir_max`? |
| Progresión | 25 % | 1RM estimado y volumen contra la sesión anterior del mismo ejercicio |
| Completitud del registro | 20 % | Proporción de series con RIR reportado |
| Constancia | 15 % | Días transcurridos contra los días planeados |

Y una **tendencia** de la calificación a lo largo de las semanas, que es lo que el
profesor pidió con «con el tiempo».

Esto conecta directamente con el modelo predictivo: la componente de progresión puede
sustituirse después por «qué tan cerca estuvo la carga real de la que el modelo predijo»,
y ahí la calificación deja de ser una fórmula y pasa a ser una medida del modelo en
operación.

**Se hace primero.** No depende de nadie.

### 2.2 Foto de comida → calorías · **viable, con una advertencia seria**

Arquitectura, dado que el sitio es estático y una llave de API no puede ir en un repo
público:

```
navegador → Edge Function de Supabase (guarda la llave) → Gemini → JSON
                                    ↓
                        la foto NO se guarda en ningún lado
```

La función recibe la imagen, la manda al modelo, devuelve `{alimentos, kcal, proteína,
carbohidratos, grasa, confianza}` y la descarta. Se cumple lo que pediste: la foto es un
escáner, no un archivo.

> **Problema de privacidad que hay que resolver antes de escribir código.**
> En el **tier gratuito**, Google puede usar lo que se le manda para mejorar sus
> productos, **incluida revisión humana**. Eso significa fotos de comida y datos de salud
> de tus participantes en manos de un tercero que puede retenerlos y revisarlos.
>
> Tu consentimiento actual dice que los registros anonimizados se usan para entrenar
> *tu* modelo. No dice nada de mandarlos a Google. Tal como está, usar el tier gratuito
> con participantes reales sería incumplir lo que firmaron.
>
> Salidas, en orden de preferencia:
> 1. **Vincular facturación** (Tier 1). En el tier de pago Google no usa las peticiones
>    para entrenar. Con Flash-Lite, un estudio de 5 personas × 3 fotos al día × 8
>    semanas sale en pocos dólares. Es la opción correcta.
> 2. Dejar la función como **demostración**, sin participantes reales.
> 3. Reescribir el consentimiento declarando el envío a un tercero. Más honesto que
>    ocultarlo, pero les da una razón para no participar.

**Segunda advertencia, esta técnica:** estimar calorías de una foto sin saber la porción
es poco confiable. Un plato de arroz puede ser 150 o 400 kcal según cuánto haya. La
función debe devolver el resultado **como estimación editable**, marcarlo con
`source = 'estimated'` en la base y no mezclarlo con lo que el usuario capturó a mano.
Esa distinción ya existe en el esquema y ahora se vuelve importante.

### 2.3 Valoración de rutinas por IA · **viable, sobre lo que ya existe**

La misma Edge Function, sin imagen. Se le manda la rutina **más el diagnóstico por reglas
que ya calculamos** y se le pide una crítica en lenguaje natural.

Las reglas se quedan como esqueleto: son deterministas, explicables y no inventan. El
modelo aporta matiz y redacción. **Los números los pone la regla, nunca el modelo** — un
LLM que estima series semanales se equivoca y no hay forma de auditarlo.

### 2.4 Imágenes de los ejercicios · **tu instinto era el correcto**

Generar una imagen por ejercicio cada vez que alguien abre la app es caro, lento y
absurdo: son 29 ejercicios fijos. Se generan **una sola vez**, se guardan como archivos y
se sirven estáticamente. Cero costo por uso, cero RAM, funciona sin conexión.

Para que haya análisis de verdad y no solo decoración, junto a cada imagen se genera una
vez —y se guarda en la base— una ficha de técnica: puntos clave de ejecución, errores
comunes y señales de que se está haciendo mal. Eso es contenido analizado por un modelo,
producido una vez y servido sin costo. Es lo que hacen las apps reales.

Si el profesor quería **analizar la técnica del usuario desde su propia foto**, eso es un
proyecto distinto y bastante más grande: estimación de pose, comparación con un patrón de
referencia, y una tasa de error que hay que medir. Vale la pena preguntarle si era eso,
porque cambia el alcance por completo.

---

## 3. Orden de trabajo

1. **Separar versiones** y clonar el esquema en `gymai-v2`.
2. **Calificación del entrenamiento.** Sin dependencias externas. Es lo que más peso
   académico agrega y lo que conecta con el modelo predictivo.
3. **Decidir lo de la facturación de Gemini.** Bloquea 2.2 y 2.3.
4. **Edge Function** con la llave, y encima la foto de comida.
5. **Valoración de rutinas**, que reutiliza la función.
6. **Biblioteca de imágenes** y fichas de técnica, generadas una vez.

Los puntos 2 y 6 se pueden hacer aunque nunca haya llave de API. Los puntos 4 y 5 no.

---

## 4. Lo que no cambia

El anteproyecto sigue en pie: el objeto de estudio es la predicción de la carga a partir
del historial, y las hipótesis no se mueven. Todo esto son funciones de producto que
mejoran la recolección y hacen la app más vistosa — pero la calificación del
entrenamiento es la única que además aporta al argumento científico, porque mide en
operación lo que el modelo promete en simulación.

Conviene decirlo así en la defensa: se distingue entre lo que hace mejor a la aplicación
y lo que sostiene la investigación. No es lo mismo, y confundirlos es lo que hace que un
proyecto se vea inflado.
