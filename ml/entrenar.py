#!/usr/bin/env python3
"""
GymAI · Entrenamiento y evaluación del modelo de progresión de cargas
=====================================================================

Entrada: un CSV con las columnas de la vista `v_ml_dataset`. Funciona
igual con datos sintéticos (`generar_datos.py`) que con el export real
de Supabase, porque las columnas son las mismas.

Qué predice
-----------
El **incremento** de carga para la siguiente sesión (`target_delta_kg`),
no la carga absoluta. Predecir la carga absoluta infla las métricas de
forma engañosa: el peso de hoy explica casi todo el de la próxima vez y
cualquier modelo parecería excelente. Predecir el delta plantea el
problema real. La carga final se reconstruye sumando y se redondea al
incremento mínimo utilizable del ejercicio, que es lo único que existe
en un gimnasio.

Validación
----------
1. Partición **temporal** por serie usuario × ejercicio: el último 25 %
   de cada historial va a prueba. Nunca se entrena con el futuro.
2. Partición por **usuario no visto**: usuarios completos fuera del
   entrenamiento, para estimar el desempeño ante alguien nuevo.

Fuga de información
-------------------
`days_to_next_session` se excluye a propósito: solo se conoce después de
que la sesión siguiente ocurrió. Usarla sería hacer trampa.
"""

from __future__ import annotations
import argparse
import numpy as np
import pandas as pd

from sklearn.compose import ColumnTransformer
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.ensemble import RandomForestRegressor, HistGradientBoostingRegressor
from sklearn.inspection import permutation_importance

# --------------------------------------------------------------------
NUM_BASE = [
    "session_no", "age_years", "height_cm", "experience_months",
    "load_increment_kg", "top_weight_kg", "avg_reps", "avg_rir", "min_rir",
    "total_volume_kg", "top_e1rm_kg",
    "prev1_weight_kg", "prev2_weight_kg", "prev3_weight_kg",
    "prev1_avg_rir", "prev2_avg_rir", "prev1_volume_kg", "prev1_e1rm_kg",
    "days_since_prev_session", "pct_change_vs_prev",
    "sleep_h_7d", "bodyweight_7d_kg",
]
NUM_NUTRI = [
    "kcal_7d", "kcal_target_7d", "kcal_balance_7d",
    "protein_7d", "protein_g_per_kg_7d", "days_logged_7d",
]
CAT = ["sex", "goal", "muscle_group", "movement_pattern", "equipment", "is_compound"]

# NO usar: days_to_next_session (se conoce solo a posteriori)


# --------------------------------------------------------------------
def cargar(ruta: str) -> pd.DataFrame:
    df = pd.read_csv(ruta)
    df = df[df["target_next_weight_kg"].notna()].copy()
    if "target_delta_kg" not in df.columns:
        df["target_delta_kg"] = df["target_next_weight_kg"] - df["top_weight_kg"]
    # Se exige algo de historial: el modelo B opera a partir de la 3a sesión
    df = df[df["session_no"] >= 3].copy()
    df["serie"] = df["user_id"].astype(str) + "|" + df["exercise_id"].astype(str)
    return df.sort_values(["serie", "performed_on"]).reset_index(drop=True)


def particion_temporal(df: pd.DataFrame, frac_prueba: float = 0.25):
    """Último tramo de cada serie a prueba. Sin mezclar pasado y futuro."""
    idx_prueba = []
    for _, g in df.groupby("serie", sort=False):
        n = len(g)
        k = max(1, int(round(n * frac_prueba)))
        idx_prueba.extend(g.index[-k:])
    mask = df.index.isin(idx_prueba)
    return df[~mask].copy(), df[mask].copy()


def particion_por_usuario(df: pd.DataFrame, frac: float = 0.25, semilla: int = 7):
    us = df["user_id"].unique()
    rng = np.random.default_rng(semilla)
    fuera = set(rng.choice(us, size=max(1, int(len(us) * frac)), replace=False))
    m = df["user_id"].isin(fuera)
    return df[~m].copy(), df[m].copy()


# --------------------------------------------------------------------
def redondear(pred_kg: np.ndarray, incremento: np.ndarray) -> np.ndarray:
    """Ajusta al múltiplo del disco/placa disponible. En el gimnasio no
    existe 63.7 kg."""
    return np.round(pred_kg / incremento) * incremento


def limitar(pred_kg: np.ndarray, actual: np.ndarray, incremento: np.ndarray) -> np.ndarray:
    """Capa de restricciones de seguridad: ninguna recomendación puede
    subir más de 2 incrementos ni más del 10 % de la carga actual."""
    tope_sup = np.minimum(actual + 2 * incremento, actual * 1.10)
    tope_inf = actual * 0.80
    return np.clip(pred_kg, tope_inf, tope_sup)


def metricas(y_real_kg, y_pred_kg, incremento) -> dict:
    err = y_pred_kg - y_real_kg
    return {
        "MAE (kg)":        float(np.mean(np.abs(err))),
        "RMSE (kg)":       float(np.sqrt(np.mean(err ** 2))),
        "±1 incremento":   float(np.mean(np.abs(err) <= incremento + 1e-9)),
        "exacto":          float(np.mean(np.abs(err) < 1e-9)),
    }


# --------------------------------------------------------------------
def lineas_base(te: pd.DataFrame) -> dict:
    """Reglas heurísticas contra las que hay que ganar."""
    actual = te["top_weight_kg"].to_numpy(float)
    inc    = te["load_increment_kg"].to_numpy(float)
    rir    = te["avg_rir"].to_numpy(float)

    out = {}
    # 1. Persistencia: repetir la misma carga
    out["Persistencia (misma carga)"] = actual.copy()
    # 2. Progresión lineal: siempre subir un incremento
    out["Progresión lineal (+1 inc.)"] = actual + inc
    # 3. Progresión lineal doble, autorregulada por RIR:
    #    sube si sobraron repeticiones, baja si se quedó corto.
    rir_lleno = np.nan_to_num(rir, nan=1.0)
    paso = np.where(rir_lleno >= 2, 1.0, np.where(rir_lleno < 1, -1.0, 0.0))
    out["Lineal doble por RIR"] = actual + paso * inc
    return out


def construir(modelo, usar_nutricion: bool):
    num = NUM_BASE + (NUM_NUTRI if usar_nutricion else [])
    pre = ColumnTransformer([
        ("num", Pipeline([("imp", SimpleImputer(strategy="median")),
                          ("esc", StandardScaler())]), num),
        ("cat", Pipeline([("imp", SimpleImputer(strategy="most_frequent")),
                          ("oh", OneHotEncoder(handle_unknown="ignore"))]), CAT),
    ])
    return Pipeline([("pre", pre), ("mod", modelo)]), num


def evaluar(nombre, modelo, tr, te, usar_nutricion=True, importancias=False):
    pipe, cols = construir(modelo, usar_nutricion)
    X_tr, y_tr = tr[cols + CAT], tr["target_delta_kg"].to_numpy(float)
    X_te       = te[cols + CAT]

    pipe.fit(X_tr, y_tr)
    delta = pipe.predict(X_te)

    actual = te["top_weight_kg"].to_numpy(float)
    inc    = te["load_increment_kg"].to_numpy(float)
    real   = te["target_next_weight_kg"].to_numpy(float)

    crudo  = actual + delta
    limitado = limitar(crudo, actual, inc)
    final  = redondear(limitado, inc)

    m = metricas(real, final, inc)
    m["nombre"] = nombre
    m["_pipe"] = pipe
    m["_cols"] = cols
    m["_recortadas"] = float(np.mean(np.abs(limitado - crudo) > 1e-9))
    return m


# --------------------------------------------------------------------
def tabla(filas, ref_mae=None):
    print(f"\n{'Modelo':<32} {'MAE kg':>8} {'RMSE':>7} {'±1 inc':>8} {'exacto':>8} {'vs base':>9}")
    print("-" * 76)
    for r in filas:
        mej = "" if ref_mae is None else f"{(ref_mae - r['MAE (kg)']) / ref_mae * 100:+7.1f} %"
        print(f"{r['nombre']:<32} {r['MAE (kg)']:>8.3f} {r['RMSE (kg)']:>7.3f} "
              f"{r['±1 incremento']*100:>7.1f}% {r['exacto']*100:>7.1f}% {mej:>9}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--datos", default="datos_sinteticos.csv")
    ap.add_argument("--semilla", type=int, default=7)
    a = ap.parse_args()

    df = cargar(a.datos)
    print("=" * 76)
    print("GymAI · Modelo de progresión de cargas")
    print("=" * 76)
    print(f"Filas utilizables : {len(df):,}")
    print(f"Usuarios          : {df['user_id'].nunique()}")
    print(f"Series usuario×ej.: {df['serie'].nunique():,}")
    print(f"Delta real medio  : {df['target_delta_kg'].mean():+.2f} kg "
          f"(desv. {df['target_delta_kg'].std():.2f})")

    # ---------------- 1. Validación temporal ----------------
    tr, te = particion_temporal(df)
    print(f"\n[1] Partición temporal — entrenamiento {len(tr):,} / prueba {len(te):,}")

    base = lineas_base(te)
    real = te["target_next_weight_kg"].to_numpy(float)
    inc  = te["load_increment_kg"].to_numpy(float)
    filas = []
    for n, p in base.items():
        m = metricas(real, redondear(p, inc), inc); m["nombre"] = n; filas.append(m)
    mejor_base = min(f["MAE (kg)"] for f in filas)

    modelos = [
        ("Ridge",              Ridge(alpha=1.0)),
        ("Random Forest",      RandomForestRegressor(n_estimators=200, min_samples_leaf=6,
                                                     n_jobs=-1, random_state=a.semilla)),
        ("Gradient Boosting",  HistGradientBoostingRegressor(max_iter=400, learning_rate=0.06,
                                                             min_samples_leaf=20,
                                                             random_state=a.semilla)),
    ]
    entrenados = []
    for n, mo in modelos:
        r = evaluar(n, mo, tr, te, usar_nutricion=True)
        entrenados.append(r); filas.append(r)

    tabla(filas, ref_mae=mejor_base)
    campeon = min(entrenados, key=lambda r: r["MAE (kg)"])
    print(f"\nMejor línea base : MAE {mejor_base:.3f} kg")
    print(f"Mejor modelo     : {campeon['nombre']} · MAE {campeon['MAE (kg)']:.3f} kg "
          f"({(mejor_base - campeon['MAE (kg)'])/mejor_base*100:+.1f} % vs. base)")
    print(f"Recomendaciones recortadas por la capa de seguridad: "
          f"{campeon['_recortadas']*100:.1f} %")

    # ---------------- 2. Usuarios no vistos ----------------
    tr2, te2 = particion_por_usuario(df, semilla=a.semilla)
    print(f"\n[2] Usuarios no vistos — entrenamiento {tr2['user_id'].nunique()} usuarios "
          f"/ prueba {te2['user_id'].nunique()}")
    filas2 = []
    real2 = te2["target_next_weight_kg"].to_numpy(float)
    inc2  = te2["load_increment_kg"].to_numpy(float)
    for n, p in lineas_base(te2).items():
        m = metricas(real2, redondear(p, inc2), inc2); m["nombre"] = n; filas2.append(m)
    base2 = min(f["MAE (kg)"] for f in filas2)
    for n, mo in modelos:
        filas2.append(evaluar(n, mo, tr2, te2, usar_nutricion=True))
    tabla(filas2, ref_mae=base2)

    # ---------------- 3. Ablación: ¿aporta la nutrición? (H2) ----------------
    print(f"\n[3] Ablación del bloque nutricional (hipótesis H2)")
    tipo = HistGradientBoostingRegressor(max_iter=400, learning_rate=0.06,
                                         min_samples_leaf=20, random_state=a.semilla)
    con  = evaluar("Con nutrición",  tipo, tr, te, usar_nutricion=True)
    sin  = evaluar("Sin nutrición",  HistGradientBoostingRegressor(
                        max_iter=400, learning_rate=0.06, min_samples_leaf=20,
                        random_state=a.semilla), tr, te, usar_nutricion=False)
    tabla([sin, con])
    dif = (sin["MAE (kg)"] - con["MAE (kg)"]) / sin["MAE (kg)"] * 100
    print(f"\nEl bloque nutricional cambia el MAE en {dif:+.2f} %")
    if abs(dif) < 1:
        print("  → Aporte marginal en estos datos. Ojo: en los sintéticos la nutrición")
        print("    influye en la adaptación de fondo, no en la decisión inmediata de carga.")

    # ---------------- 4. Importancia de variables ----------------
    print(f"\n[4] Variables más informativas ({campeon['nombre']}, permutación)")
    cols = campeon["_cols"]
    # Submuestra para que el cálculo sea rápido; la importancia relativa es estable
    muestra = te.sample(min(len(te), 1500), random_state=a.semilla)
    imp = permutation_importance(campeon["_pipe"], muestra[cols + CAT],
                                 muestra["target_delta_kg"].to_numpy(float),
                                 n_repeats=3, random_state=a.semilla, n_jobs=2)
    orden = np.argsort(imp.importances_mean)[::-1][:12]
    nombres = list(te[cols + CAT].columns)
    for i in orden:
        print(f"   {nombres[i]:<28} {imp.importances_mean[i]:+.4f}")

    print("\n" + "=" * 76)
    print("Recordatorio: estos resultados provienen de datos SIMULADOS. Validan el")
    print("método y el flujo, no constituyen evidencia sobre el fenómeno real.")
    print("=" * 76)


if __name__ == "__main__":
    main()
