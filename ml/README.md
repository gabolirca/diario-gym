# Motor predictivo · GymAI

Fase 3. Modelo que predice la carga de la siguiente sesión por ejercicio.

```bash
pip install numpy pandas scikit-learn
python generar_datos.py --usuarios 60 --semanas 18 --salida datos_sinteticos.csv
python entrenar.py --datos datos_sinteticos.csv
```

- `muestra_datos_sinteticos.csv` — 5 usuarios, 12 semanas, 410 filas. Está en el repo
  para que puedas abrirlo y ver cómo se ven los datos sin ejecutar nada.
- `resultados_ejemplo.txt` — salida completa de la corrida documentada abajo.
- El CSV grande no se versiona: se reproduce con la misma semilla cuando haga falta.

---

## 1. Cómo está planteado el problema

El modelo predice el **incremento** de carga (`target_delta_kg`), no la carga absoluta.
Predecir la carga absoluta infla las métricas de forma engañosa: el peso de hoy explica
casi todo el de la próxima vez, y cualquier modelo parecería excelente. El delta plantea
el problema real.

La predicción pasa después por dos filtros que reflejan el gimnasio real:

- **Redondeo** al incremento mínimo del ejercicio (2.5 kg en barra, 5 kg en máquina).
  No existe 63.7 kg.
- **Capa de seguridad**: nunca más de 2 incrementos ni más del 10 % de subida, ni menos
  del 80 % de la carga actual. En la corrida de ejemplo recortó el 6.1 % de las
  recomendaciones.

---

## 2. Generador de datos sintéticos

No hay datos reales todavía. `generar_datos.py` simula usuarios con un modelo de
impulso-respuesta (condición-fatiga), la familia que Banister propuso para resistencia,
adaptada a fuerza:

```
potencial(t)   crece con el entrenamiento acumulado, con rendimientos decrecientes,
               modulado por balance energético, proteína y sueño
fatiga(t)      se acumula por sesión y decae exponencialmente (tau más corta)
capacidad(t)   = potencial(t) − fatiga(t)
```

El usuario **no conoce** su capacidad: elige la carga con una regla de autorregulación
ruidosa a partir del RIR que percibió. Cada usuario tiene sus propias constantes de
tiempo, respuesta individual, adherencia, sesgo alimentario y precisión al estimar el RIR.

Esto importa: **el proceso generador no es la regla de progresión lineal que sirve de
línea base**. Si lo fuera, la comparación estaría amañada y cualquier modelo la ganaría
por construcción.

El CSV que produce tiene exactamente las columnas de la vista `v_ml_dataset`, así que
`entrenar.py` corre sin cambios sobre datos simulados o reales.

---

## 3. Validación

Dos particiones, ninguna aleatoria:

1. **Temporal por serie** usuario × ejercicio: el último 25 % de cada historial va a
   prueba. Nunca se entrena con el futuro.
2. **Usuarios no vistos**: usuarios completos fuera del entrenamiento, para estimar el
   desempeño ante alguien nuevo.

Se excluyó `days_to_next_session` a propósito: solo se conoce después de que la sesión
siguiente ocurrió. Usarla sería fuga de información.

---

## 4. Resultados (60 usuarios simulados, 18 semanas, 5 954 filas)

### Partición temporal

| Modelo | MAE (kg) | RMSE | ±1 incremento | Exacto | vs. base |
|---|---:|---:|---:|---:|---:|
| Persistencia (misma carga) | 1.796 | 2.848 | 92.2 % | 49.6 % | — |
| Progresión lineal (+1 inc.) | 3.412 | 4.248 | 72.9 % | 16.1 % | −90.0 % |
| Lineal doble por RIR | 1.848 | 2.682 | 96.9 % | 42.8 % | −2.9 % |
| Ridge | 1.323 | 2.331 | 95.6 % | 60.6 % | +26.3 % |
| **Random Forest** | **0.951** | **2.044** | **95.6 %** | **72.9 %** | **+47.0 %** |
| Gradient Boosting | 0.995 | 2.094 | 95.6 % | 72.0 % | +44.6 % |

La capa de seguridad recortó el 17.5 % de las recomendaciones.

### Usuarios no vistos

Random Forest: MAE **0.874 kg**, +50.2 % sobre la mejor línea base. Igual o mejor que en
la partición temporal, lo cual sugiere que el modelo generaliza a personas nuevas y no
solo memoriza a quienes ya vio.

### Contra los criterios del anteproyecto

| Criterio | Meta | Resultado | |
|---|---|---|---|
| MAE | < 2.5 kg (1 incremento) | 0.951 kg | ✅ |
| Exactitud ±1 incremento | > 75 % | 95.6 % | ✅ |
| Mejora sobre línea base | ≥ 20 % | +47.0 % | ✅ |
| Aporte del bloque nutricional | no nulo | −2.1 % | ❌ |

> **Nota sobre estas cifras.** Son la segunda versión. La primera corrida daba MAE de
> 1.335 kg, pero al auditar el generador se encontró que la adaptación estaba modelada
> en kilos absolutos y no en porcentaje: los ejercicios ligeros crecían **+259 % en 18
> semanas**, lo cual es fisiológicamente absurdo. Corregido a ganancia relativa con
> rendimientos decrecientes, la progresión mediana quedó en +6.2 % en 18 semanas
> (+16.7 % en principiantes con cargas bajas, +4 a 5 % en levantadores fuertes), que sí
> concuerda con la literatura. Los resultados de arriba son los de la versión corregida.

---

## 5. El hallazgo incómodo: H2 no se sostiene como está escrita

**Quitar el bloque nutricional no empeora el modelo: lo mejora un 2.1 %.** O sea, las
variables de comida no solo no aportan, meten algo de ruido.

No es un error del código, y conviene entender por qué antes de defender el trabajo.

En el generador la nutrición **sí** afecta la fuerza: modula la tasa de adaptación del
potencial. Pero su efecto sobre la carga de la *siguiente sesión* llega **mediado por el
RIR**. Si comes mal, te recuperas peor, te sobran menos repeticiones, reportas un RIR más
bajo — y el modelo ya está viendo ese RIR. La nutrición no agrega información que el RIR
no haya traído ya.

Dicho de otro modo: **en un horizonte de una sesión, el RIR absorbe el efecto
nutricional**. Es un resultado esperable a posteriori, pero solo se ve al construir el
modelo.

### Qué hacer con esto

Reformular H2 a un **horizonte largo**, donde el efecto sí tiene dónde acumularse:

> *H2 (revisada).* El bloque nutricional mejora significativamente la predicción del
> **cambio del 1RM estimado a 4 semanas**, respecto del mismo modelo entrenado solo con
> variables de desempeño y antropometría.

Eso es contrastable, es coherente con la fisiología y sigue siendo el aporte
diferenciador del proyecto. La versión de una sesión no lo es, y sostenerla sería
defender algo que los propios datos ya contradicen.

---

## 6. Qué está aprendiendo el modelo en realidad

Vale la pena decirlo con claridad, porque un revisor lo va a preguntar.

Sobre datos sintéticos, el modelo aprende sobre todo **la regla de autorregulación del
usuario simulado**, no fisiología pura. Las variables más informativas lo delatan:

```
avg_reps                 +0.376     ¿completó las repeticiones objetivo?
pct_change_vs_prev       +0.270     inercia: qué hizo la última vez
min_rir                  +0.241
avg_rir                  +0.217
prev1_avg_rir            +0.080
kcal_balance_7d          +0.013     ← nutrición, casi al final
```

Las señales de esfuerzo y la inercia dominan. Eso es exactamente lo que debería pasar y no invalida nada: sobre datos
reales el modelo aprenderá cómo autorregula *esa* persona, que es justo lo que se busca
en un sistema personalizado. Pero la afirmación honesta es «el modelo aprende a
anticipar la decisión de carga», no «el modelo descubre la fisiología del usuario».

---

## 7. Limitaciones

1. **Los datos son simulados.** Validan el método y el flujo; no son evidencia sobre el
   fenómeno real. Así debe declararse en el documento.
2. El generador incorpora los supuestos del autor sobre cómo progresa la fuerza. Si esos
   supuestos están mal, los resultados heredan el error. Ya pasó una vez: ver la nota de
   la sección 4 sobre la adaptación absoluta contra relativa. Conviene auditar el
   generador contra la literatura antes de citarlo en el documento.
3. `session_no >= 3` es el filtro actual; H3 propone 6 sesiones. Falta medir la curva de
   MAE contra número de sesiones para fijarlo con datos.
4. Falta el modelo de arranque en frío con OpenPowerlifting y el clasificador de descarga.

---

## 8. Siguiente

- [ ] Curva de MAE contra número de sesiones, para fijar el umbral de H3 con evidencia
- [ ] Modelo de arranque en frío (OpenPowerlifting)
- [ ] Servicio de inferencia que escriba en `predictions` y cierre el ciclo de medición
- [ ] Reentrenar con datos reales cuando haya historial
