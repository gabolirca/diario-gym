#!/usr/bin/env python3
"""
GymAI · Generador de datos sintéticos de entrenamiento de fuerza
================================================================

Produce un CSV con exactamente las mismas columnas que la vista
`v_ml_dataset` de Supabase, de modo que `entrenar.py` funcione sin
cambios sobre datos simulados o reales.

Por qué existe
--------------
No hay datos reales todavía y no habrá suficientes en semanas. Este
generador permite construir y validar todo el flujo de entrenamiento
antes de tenerlos. Su función es metodológica, no probatoria: los
resultados obtenidos aquí NO son evidencia sobre el fenómeno real y así
debe declararse en el documento.

Modelo generador
----------------
Se usa una estructura de impulso-respuesta (condición-fatiga), la misma
familia de modelos que Banister propuso para deportes de resistencia,
adaptada a fuerza:

    potencial(t)  crece con el entrenamiento acumulado, con rendimientos
                  decrecientes, modulado por balance energético, proteína
                  y sueño.
    fatiga(t)     se acumula con cada sesión y decae exponencialmente,
                  con constante de tiempo más corta que la adaptación.
    capacidad(t)  = potencial(t) - fatiga(t)      (1RM expresable hoy)

El usuario NO conoce su capacidad: elige la carga con una regla de
autorregulación ruidosa basada en el RIR que percibió la última vez.

Esto es importante: el proceso generador **no es** la regla de progresión
lineal que sirve de línea base. Si lo fuera, la comparación estaría
amañada y cualquier modelo la ganaría por construcción.
"""

from __future__ import annotations
import argparse
import numpy as np
import pandas as pd

# --------------------------------------------------------------------
# Catálogo: refleja el de la base (tabla exercises)
# --------------------------------------------------------------------
EJERCICIOS = [
    # slug, grupo, patrón, equipo, compuesto, incremento, 1RM rel. al peso corporal (hombre entrenado)
    ("press-banca-inclinado", "pecho",      "empuje_horizontal", "barra",     True,  2.5, 0.90),
    ("press-militar-barra",   "hombro",     "empuje_vertical",   "barra",     True,  2.5, 0.60),
    ("sentadilla-hack",       "cuadriceps", "sentadilla",        "maquina",   True,  5.0, 1.50),
    ("peso-muerto",           "isquios",    "bisagra",           "barra",     True,  2.5, 1.80),
    ("jalon-al-pecho",        "espalda",    "jale_vertical",     "polea",     True,  2.5, 0.85),
    ("curl-biceps-barra",     "biceps",     "aislamiento",       "barra",     False, 2.5, 0.45),
    ("extension-cuadriceps",  "cuadriceps", "aislamiento",       "maquina",   False, 5.0, 0.70),
    ("elevaciones-laterales", "hombro",     "aislamiento",       "mancuerna", False, 2.0, 0.15),
]

# Repeticiones objetivo y ventana de RIR por tipo de ejercicio
REPS_OBJ = {True: 8, False: 12}          # compuesto / aislamiento
RIR_OBJ  = {True: (1, 3), False: (0, 2)}


def epley_reps(capacidad_1rm: float, carga: float) -> float:
    """Repeticiones máximas posibles con esa carga, invirtiendo Epley."""
    if carga <= 0 or carga >= capacidad_1rm:
        return 0.0
    return 30.0 * (capacidad_1rm / carga - 1.0)


def f_energia(balance_kcal: float) -> float:
    """Multiplicador de adaptación según el balance energético diario.

    Déficit agresivo frena la ganancia de fuerza sin anularla; el superávit
    la acelera un poco. Curva suave, sin escalones artificiales.
    """
    return float(np.clip(1.0 + balance_kcal / 1400.0, 0.35, 1.25))


def f_proteina(g_por_kg: float) -> float:
    """Saturante alrededor de 1.6 g/kg: más allá aporta poco."""
    return float(np.clip(0.55 + 0.45 * min(g_por_kg, 1.8) / 1.6, 0.55, 1.0))


def f_sueno(horas: float) -> float:
    """Penaliza por debajo de 7 h; arriba de 8 no suma."""
    return float(np.clip(0.70 + 0.30 * (horas - 5.0) / 3.0, 0.70, 1.0))


def simular_usuario(rng: np.random.Generator, uid: int, semanas: int) -> pd.DataFrame:
    # ---------------- Perfil ----------------
    sexo        = rng.choice(["M", "F"], p=[0.7, 0.3])
    edad        = float(np.clip(rng.normal(26, 5), 18, 55).round(1))
    estatura    = float(np.clip(rng.normal(172 if sexo == "M" else 161, 7), 150, 195).round(1))
    peso0       = float(np.clip(rng.normal(78 if sexo == "M" else 64, 11), 45, 130).round(1))
    exp_meses   = float(np.clip(rng.gamma(2.2, 9), 1, 140).round(1))
    objetivo    = rng.choice(["recomp", "fat_loss", "muscle_gain"], p=[0.45, 0.35, 0.20])

    # Un principiante responde más rápido; la respuesta se agota con los años
    novato      = float(np.clip(1.9 - 0.55 * np.log1p(exp_meses), 0.45, 1.9))
    respondedor = float(np.clip(rng.normal(1.0, 0.28), 0.4, 1.8))   # variación individual real
    fuerza_rel  = 1.0 if sexo == "M" else 0.62

    # Constantes de tiempo del modelo condición-fatiga (días)
    tau_fit     = float(rng.uniform(28, 48))
    tau_fat     = float(rng.uniform(6, 14))
    k_fat       = float(rng.uniform(0.9, 1.8))

    # Hábitos
    adherencia  = float(np.clip(rng.normal(0.84, 0.11), 0.45, 1.0))
    sueno_medio = float(np.clip(rng.normal(7.1, 0.8), 5.0, 9.0))
    kcal_obj    = float(np.round(rng.normal(2250 if sexo == "M" else 1850, 260)))
    # Qué tan bien cumple el plan: algunos comen de más de forma sistemática
    sesgo_kcal  = float(rng.normal(-120 if objetivo == "fat_loss" else 40, 160))
    prot_kg     = float(np.clip(rng.normal(1.6, 0.45), 0.6, 2.8))
    ruido_rir   = float(rng.uniform(0.35, 0.95))   # qué tan mal estima su RIR

    # ---------------- Estado por ejercicio ----------------
    n_ej   = rng.integers(4, len(EJERCICIOS) + 1)
    elegidos = rng.choice(len(EJERCICIOS), size=n_ej, replace=False)

    estado = {}
    for idx in elegidos:
        slug, grupo, patron, equipo, comp, inc, rel = EJERCICIOS[idx]
        pot0 = peso0 * rel * fuerza_rel * float(np.clip(rng.normal(1.0, 0.16), 0.6, 1.5))
        pot0 *= float(np.clip(0.68 + 0.32 * min(exp_meses, 60) / 60, 0.68, 1.0))
        reps = REPS_OBJ[comp]
        # Carga inicial: la que deja ~2 RIR con las reps objetivo
        carga0 = pot0 / (1 + (reps + 2) / 30.0)
        estado[idx] = dict(pot=pot0, fatiga=0.0,
                           carga=round(carga0 / inc) * inc,
                           inc=inc, reps=reps, comp=comp,
                           rel=rel,                 # 1RM de referencia relativo al peso corporal
                           duras=0,                 # sesiones duras consecutivas
                           ultimo_dia=None, hist=[])

    # ---------------- Calendario ----------------
    dias_entreno = [0, 2, 4]          # lun, mié, vie
    filas = []
    peso_actual = peso0

    for semana in range(semanas):
        # Cada semana el usuario come y duerme con variación
        kcal_sem  = kcal_obj + sesgo_kcal + rng.normal(0, 130)
        balance   = kcal_sem - kcal_obj
        prot_sem  = float(np.clip(prot_kg * peso_actual + rng.normal(0, 12), 20, 400))
        sueno_sem = float(np.clip(rng.normal(sueno_medio, 0.45), 4, 10))

        # El peso corporal sigue al balance energético (7700 kcal ≈ 1 kg)
        peso_actual = float(np.clip(peso_actual + (balance * 7) / 7700.0 + rng.normal(0, 0.18), 40, 160))

        mult = (f_energia(balance) * f_proteina(prot_sem / peso_actual)
                * f_sueno(sueno_sem) * respondedor * novato)

        for d in dias_entreno:
            dia = semana * 7 + d
            if rng.random() > adherencia:
                continue                                    # sesión perdida

            # En cada sesión se entrenan 2-3 de sus ejercicios
            hoy = rng.choice(list(estado.keys()),
                             size=min(len(estado), rng.integers(2, 4)), replace=False)
            for idx in hoy:
                st = estado[idx]
                dias_desde = None if st["ultimo_dia"] is None else dia - st["ultimo_dia"]

                # --- Decaimiento de la fatiga desde la última sesión ---
                if dias_desde is not None:
                    st["fatiga"] *= np.exp(-dias_desde / tau_fat)

                capacidad = max(st["pot"] - st["fatiga"], st["pot"] * 0.55)

                # --- El usuario ejecuta la carga que traía planeada ---
                carga = st["carga"]
                reps_obj = st["reps"]
                reps_max = epley_reps(capacidad, carga)
                rir_real = reps_max - reps_obj

                # Si no le alcanza para las reps objetivo, hace menos
                reps_hechas = int(np.clip(round(min(reps_obj, reps_max)), 1, 30))
                rir_real = max(rir_real, 0.0)
                rir_obs = float(np.clip(round(rir_real + rng.normal(0, ruido_rir)), 0, 6))

                st["hist"].append(dict(dia=dia, carga=carga, reps=reps_hechas,
                                       rir=rir_obs, semana=semana,
                                       dias_desde=dias_desde,
                                       balance=balance, prot=prot_sem,
                                       sueno=sueno_sem, peso=peso_actual,
                                       kcal=kcal_sem, kcal_obj=kcal_obj))

                # --- Efecto de la sesión ---
                # La fatiga sí es absoluta: depende del trabajo mecánico total
                impulso = carga * reps_hechas * (3 if st["comp"] else 2) / 1000.0
                st["fatiga"] += k_fat * impulso

                # La adaptación es RELATIVA, no absoluta. Un levantador de 150 kg no
                # gana los mismos kilos por sesión que uno de 40 kg; ambos ganan un
                # porcentaje, y ese porcentaje se achica conforme uno se acerca a su
                # techo. Modelarlo en kilos absolutos hacía que los ejercicios ligeros
                # crecieran cientos de por ciento en unas semanas.
                nivel = st["pot"] / max(peso_actual * st["rel"], 1e-6)   # 1.0 = estándar entrenado
                techo = float(np.exp(-max(nivel - 0.45, 0.0) * 1.7))
                ganancia_rel = mult * 0.0065 * techo                     # ~0.65 %/sesión en un novato
                st["pot"] *= (1.0 + ganancia_rel)
                st["ultimo_dia"] = dia

                # --- Autorregulación del usuario para la PRÓXIMA vez ---
                # Nadie baja el peso por una sola sesión dura: hacen falta dos
                # seguidas. Sin esto la carga rebota entre dos valores para siempre.
                rmin, rmax = RIR_OBJ[st["comp"]]
                inc = st["inc"]
                duro = (rir_obs < rmin) or (reps_hechas < reps_obj)
                st["duras"] = st["duras"] + 1 if duro else 0

                if rir_obs > rmax:                      # sobró demasiado
                    paso = 2 if rir_obs >= rmax + 2 else 1
                elif st["duras"] >= 2:                  # dos sesiones duras seguidas
                    paso = -1
                    st["duras"] = 0
                elif duro:
                    paso = 0                            # aguanta y reintenta
                else:
                    paso = 1 if rng.random() < 0.40 else 0
                if rng.random() < 0.06:                 # despiste: repite o salta
                    paso += rng.choice([-1, 0, 1])
                st["carga"] = max(inc, round((carga + paso * inc) / inc) * inc)

    # ---------------- Construcción de filas al estilo v_ml_dataset ----------------
    for idx, st in estado.items():
        slug, grupo, patron, equipo, comp, inc, _ = EJERCICIOS[idx]
        h = st["hist"]
        for i, s in enumerate(h):
            prev = lambda k, n: (h[i - n][k] if i >= n else None)
            sig  = h[i + 1] if i + 1 < len(h) else None
            filas.append(dict(
                user_id=f"sim-{uid:03d}", exercise_id=slug, performed_on=int(s["dia"]),
                session_no=i + 1,
                sex=sexo, age_years=edad, height_cm=estatura,
                experience_months=exp_meses + s["semana"] / 4.34, goal=objetivo,
                muscle_group=grupo, movement_pattern=patron, equipment=equipo,
                is_compound=comp, load_increment_kg=inc,
                top_weight_kg=s["carga"], avg_reps=s["reps"], avg_rir=s["rir"],
                min_rir=s["rir"], n_sets=3, n_sets_with_rir=3,
                total_volume_kg=s["carga"] * s["reps"] * 3,
                top_e1rm_kg=s["carga"] * (1 + s["reps"] / 30.0),
                prev1_weight_kg=prev("carga", 1), prev2_weight_kg=prev("carga", 2),
                prev3_weight_kg=prev("carga", 3),
                prev1_avg_rir=prev("rir", 1), prev2_avg_rir=prev("rir", 2),
                prev1_volume_kg=(None if i < 1 else h[i-1]["carga"] * h[i-1]["reps"] * 3),
                prev1_e1rm_kg=(None if i < 1 else h[i-1]["carga"] * (1 + h[i-1]["reps"] / 30.0)),
                days_since_prev_session=s["dias_desde"],
                pct_change_vs_prev=(None if i < 1 or not h[i-1]["carga"] else
                                    round((s["carga"] - h[i-1]["carga"]) / h[i-1]["carga"] * 100, 2)),
                days_to_next_session=(None if sig is None else sig["dia"] - s["dia"]),
                sleep_h_7d=round(s["sueno"], 2),
                bodyweight_7d_kg=round(s["peso"], 2),
                kcal_7d=round(s["kcal"]), kcal_target_7d=round(s["kcal_obj"]),
                kcal_balance_7d=round(s["kcal"] - s["kcal_obj"]),
                protein_7d=round(s["prot"], 1),
                protein_g_per_kg_7d=round(s["prot"] / s["peso"], 2),
                days_logged_7d=7,
                # OBJETIVO: la carga que el usuario realmente usó la siguiente vez
                target_next_weight_kg=(None if sig is None else sig["carga"]),
            ))

    df = pd.DataFrame(filas)
    if not df.empty:
        df["target_delta_kg"] = df["target_next_weight_kg"] - df["top_weight_kg"]
    return df


def main():
    ap = argparse.ArgumentParser(description="Genera datos sintéticos de entrenamiento de fuerza.")
    ap.add_argument("--usuarios", type=int, default=120)
    ap.add_argument("--semanas",  type=int, default=20)
    ap.add_argument("--semilla",  type=int, default=42)
    ap.add_argument("--salida",   type=str, default="datos_sinteticos.csv")
    a = ap.parse_args()

    rng = np.random.default_rng(a.semilla)
    partes = [simular_usuario(rng, u, a.semanas) for u in range(a.usuarios)]
    df = pd.concat([p for p in partes if not p.empty], ignore_index=True)

    df.to_csv(a.salida, index=False)
    con_obj = df["target_next_weight_kg"].notna().sum()
    print(f"Usuarios simulados      : {a.usuarios}")
    print(f"Semanas por usuario     : {a.semanas}")
    print(f"Filas totales           : {len(df):,}")
    print(f"Filas con objetivo      : {con_obj:,}")
    print(f"Sesiones por usuario    : {len(df)/a.usuarios:.1f}")
    print(f"Cambio de carga (media) : {df['target_delta_kg'].mean():.2f} kg")
    print(f"  se mantiene igual     : {(df['target_delta_kg']==0).mean()*100:.1f} %")
    print(f"  sube                  : {(df['target_delta_kg']>0).mean()*100:.1f} %")
    print(f"  baja                  : {(df['target_delta_kg']<0).mean()*100:.1f} %")
    print(f"Guardado en             : {a.salida}")


if __name__ == "__main__":
    main()
