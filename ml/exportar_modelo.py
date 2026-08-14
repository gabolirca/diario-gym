"""
Entrena el modelo de carga y lo exporta a un JSON que se puede evaluar sin
scikit-learn.

Por qué exportar en vez de servir Python: la app necesita la sugerencia en el
momento en que abres la pestaña de Pesas. Un script que hay que correr a mano
deja la recomendación desactualizada, y en una demostración obliga a depender
de una laptop encendida. Un bosque de árboles es, al final, una lista de
comparaciones: cabe en un archivo y se recorre en veinte líneas de código.

El precio es que los árboles tienen que ser más pequeños para que el archivo no
pese de más. Este script imprime el MAE del modelo grande y del exportado, para
que la diferencia esté a la vista y no escondida.

    python3 exportar_modelo.py --datos datos_sinteticos.csv --salida modelo.json
"""
from __future__ import annotations

import argparse
import json
import gzip
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor

# Mismas variables que entrenar.py. Sin escalar: a un árbol le da igual la
# escala, y quitar el escalador elimina una fuente de desajuste entre lo que
# calcula Python y lo que calcula la app.
NUM = [
    "session_no", "age_years", "height_cm", "experience_months",
    "load_increment_kg", "top_weight_kg", "avg_reps", "avg_rir", "min_rir",
    "total_volume_kg", "top_e1rm_kg",
    "prev1_weight_kg", "prev2_weight_kg", "prev3_weight_kg",
    "prev1_avg_rir", "prev2_avg_rir", "prev1_volume_kg", "prev1_e1rm_kg",
    "days_since_prev_session", "pct_change_vs_prev",
    "sleep_h_7d", "bodyweight_7d_kg",
    "kcal_7d", "kcal_target_7d", "kcal_balance_7d",
    "protein_7d", "protein_g_per_kg_7d", "days_logged_7d",
]
CAT = ["sex", "goal", "muscle_group", "movement_pattern", "equipment", "is_compound"]


# A partir de qué sesión del MISMO ejercicio se puede sugerir. Con 2 basta:
# medido, el error no empeora, y significa que la persona recibe algo útil en
# su segunda visita en vez de a las tres semanas. Esperar de más es la forma
# más rápida de que abandone el estudio.
MIN_SESIONES = 2


def cargar(ruta: str, min_sesiones: int = MIN_SESIONES) -> pd.DataFrame:
    df = pd.read_csv(ruta)
    df = df[df["target_next_weight_kg"].notna()].copy()
    df["target_delta_kg"] = df["target_next_weight_kg"] - df["top_weight_kg"]
    df = df[df["session_no"] >= min_sesiones].copy()
    df["serie"] = df["user_id"].astype(str) + "|" + df["exercise_id"].astype(str)
    return df.sort_values(["serie", "performed_on"]).reset_index(drop=True)


def particion_temporal(df, frac=0.25):
    """El tramo final de cada serie va a prueba. Nunca se entrena con el futuro."""
    idx = []
    for _, g in df.groupby("serie", sort=False):
        idx.extend(g.index[-max(1, int(round(len(g) * frac))):])
    m = df.index.isin(idx)
    return df[~m].copy(), df[m].copy()


def particion_por_usuario(df, frac=0.25, semilla=7):
    us = df["user_id"].unique()
    fuera = set(np.random.default_rng(semilla).choice(us, max(1, int(len(us) * frac)), replace=False))
    m = df["user_id"].isin(fuera)
    return df[~m].copy(), df[m].copy()


class Codificador:
    """Convierte una fila en el vector de números que espera el bosque.
    Se guarda junto al modelo para que la app arme el vector igual."""

    def __init__(self, df: pd.DataFrame):
        self.medianas = {c: float(np.nanmedian(pd.to_numeric(df[c], errors="coerce")))
                         for c in NUM}
        self.categorias = {c: sorted(map(str, pd.Series(df[c]).dropna().unique())) for c in CAT}
        self.nombres = list(NUM) + [f"{c}={v}" for c in CAT for v in self.categorias[c]]

    def matriz(self, df: pd.DataFrame) -> np.ndarray:
        partes = [pd.to_numeric(df[c], errors="coerce").fillna(self.medianas[c]).to_numpy(float)
                  for c in NUM]
        for c in CAT:
            col = df[c].astype(str)
            for v in self.categorias[c]:
                partes.append((col == v).to_numpy(float))
        return np.column_stack(partes)


def redondear(kg, inc):
    """En el gimnasio no existe 63.7 kg: se ajusta al disco disponible."""
    return np.round(kg / inc) * inc


def limitar(kg, actual, inc):
    """Ninguna sugerencia puede subir más de dos discos ni más del 10 %,
    ni bajar más del 20 %. El modelo propone; esta capa impide disparates."""
    return np.clip(kg, actual * 0.80, np.minimum(actual + 2 * inc, actual * 1.10))


def medir(pred_kg, real_kg, inc):
    err = pred_kg - real_kg
    return {"mae": float(np.mean(np.abs(err))),
            "rmse": float(np.sqrt(np.mean(err ** 2))),
            "dentro_1_disco": float(np.mean(np.abs(err) <= inc + 1e-9))}


def evaluar(mod, cod, te):
    actual = te["top_weight_kg"].to_numpy(float)
    inc    = te["load_increment_kg"].to_numpy(float)
    real   = te["target_next_weight_kg"].to_numpy(float)
    pred   = limitar(redondear(actual + mod.predict(cod.matriz(te)), inc), actual, inc)
    return medir(pred, real, inc)


def lineas_base(te):
    actual = te["top_weight_kg"].to_numpy(float)
    inc    = te["load_increment_kg"].to_numpy(float)
    real   = te["target_next_weight_kg"].to_numpy(float)
    rir    = np.nan_to_num(te["avg_rir"].to_numpy(float), nan=1.0)
    paso   = np.where(rir >= 2, 1.0, np.where(rir < 1, -1.0, 0.0))
    return {
        "Persistencia (misma carga)": medir(actual, real, inc),
        "Progresión lineal (+1 disco)": medir(actual + inc, real, inc),
        "Lineal doble por RIR": medir(actual + paso * inc, real, inc),
    }


def exportar_arbol(t) -> dict:
    """Un árbol de sklearn en su forma mínima: para cada nodo, qué variable
    mira, con qué umbral compara y a dónde va. Las hojas llevan el valor."""
    a = t.tree_
    return {
        "f": [int(x) for x in a.feature],                       # -2 en las hojas
        "u": [round(float(x), 6) for x in a.threshold],
        "i": [int(x) for x in a.children_left],
        "d": [int(x) for x in a.children_right],
        "v": [round(float(a.value[n][0][0]), 6) for n in range(a.node_count)],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--datos",  default="datos_sinteticos.csv")
    ap.add_argument("--salida", default="modelo.json")
    ap.add_argument("--arboles", type=int, default=120)
    ap.add_argument("--profundidad", type=int, default=8)
    ap.add_argument("--hoja", type=int, default=12)
    a = ap.parse_args()

    df = cargar(a.datos)
    tr, te = particion_temporal(df)
    tr2, te2 = particion_por_usuario(df)
    cod = Codificador(tr)
    y = tr["target_delta_kg"].to_numpy(float)

    print(f"Filas: {len(df):,}  ·  entrenamiento {len(tr):,}  ·  prueba {len(te):,}")
    print(f"Variables: {len(cod.nombres)}\n")

    print("Líneas base (partición temporal)")
    for n, m in lineas_base(te).items():
        print(f"  {n:<30} MAE {m['mae']:.3f} kg")
    mejor_base = min(m["mae"] for m in lineas_base(te).values())

    # El modelo de referencia, sin restricciones de tamaño
    grande = RandomForestRegressor(n_estimators=200, min_samples_leaf=6,
                                   n_jobs=-1, random_state=0)
    grande.fit(cod.matriz(tr), y)
    mg = evaluar(grande, cod, te)

    # El que se va a exportar: árboles recortados para que el archivo sea manejable
    chico = RandomForestRegressor(n_estimators=a.arboles, max_depth=a.profundidad,
                                  min_samples_leaf=a.hoja, n_jobs=-1, random_state=0)
    chico.fit(cod.matriz(tr), y)
    mc = evaluar(chico, cod, te)

    tr2c = Codificador(tr2)
    chico2 = RandomForestRegressor(n_estimators=a.arboles, max_depth=a.profundidad,
                                   min_samples_leaf=a.hoja, n_jobs=-1, random_state=0)
    chico2.fit(tr2c.matriz(tr2), tr2["target_delta_kg"].to_numpy(float))
    mu = evaluar(chico2, tr2c, te2)

    print(f"\n{'Modelo':<34}{'MAE':>8}{'RMSE':>8}{'±1 disco':>11}{'vs base':>10}")
    for n, m in [("Bosque completo (200 árboles)", mg),
                 (f"Bosque exportable ({a.arboles}×{a.profundidad})", mc)]:
        print(f"  {n:<32}{m['mae']:>8.3f}{m['rmse']:>8.3f}{m['dentro_1_disco']*100:>10.1f}%"
              f"{(1-m['mae']/mejor_base)*100:>9.1f}%")
    print(f"  {'Exportable, usuarios nuevos':<32}{mu['mae']:>8.3f}{mu['rmse']:>8.3f}"
          f"{mu['dentro_1_disco']*100:>10.1f}%")

    modelo = {
        "version": "carga-v1",
        "min_sesiones": MIN_SESIONES,
        "objetivo": "delta_kg",       # el bosque predice el CAMBIO, no la carga
        "entrenado_con": "datos sintéticos",
        "filas_entrenamiento": int(len(tr)),
        "mae_kg": round(mc["mae"], 4),
        "mae_usuarios_nuevos_kg": round(mu["mae"], 4),
        "mejor_linea_base_kg": round(mejor_base, 4),
        "numericas": NUM,
        "medianas": {k: round(v, 6) for k, v in cod.medianas.items()},
        "categoricas": cod.categorias,
        "arboles": [exportar_arbol(t) for t in chico.estimators_],
    }

    with open(a.salida, "w", encoding="utf-8") as f:
        json.dump(modelo, f, separators=(",", ":"))
    crudo = len(json.dumps(modelo, separators=(",", ":")).encode())
    print(f"\nGuardado en {a.salida}")
    print(f"  {crudo/1024:,.0f} KB  ·  {len(gzip.compress(json.dumps(modelo).encode()))/1024:,.0f} KB comprimido"
          f"  ·  {sum(len(t['f']) for t in modelo['arboles']):,} nodos")

    # Muestra para comprobar que la app calcula lo mismo que aquí
    m = cod.matriz(te.head(50))
    with open(a.salida.replace(".json", "_muestra.json"), "w", encoding="utf-8") as f:
        json.dump({"vectores": [[round(float(x), 6) for x in fila] for fila in m],
                   "esperado": [round(float(x), 6) for x in chico.predict(m)]}, f)
    print(f"  muestra de verificación: {a.salida.replace('.json', '_muestra.json')}")


if __name__ == "__main__":
    main()
