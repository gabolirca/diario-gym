# Base de datos · GymAI

La base ya está creada y migrada en Supabase. Este archivo explica cómo bajarla al repo
para que quede versionada junto con el código.

## Proyecto

| | |
|---|---|
| Nombre | `gymai` |
| Ref | `ckvogrrzhdfdubqcwayn` |
| URL | `https://ckvogrrzhdfdubqcwayn.supabase.co` |
| Región | `us-east-2` |
| Plan | Free · $0/mes |
| Postgres | 17.6 |

Clave publicable (segura para el cliente, va en `index.html`):

```
sb_publishable_sTfMoFyH0WHOGpFIlSu1Eg_6yy0QNVX
```

> La clave publicable puede estar en el repo: no da acceso a nada que las políticas RLS
> no permitan. La que **nunca** debe subirse es la `service_role`.

## Migraciones

Las 12 migraciones ya están en `supabase/migrations/`, con los mismos timestamps que el
historial del servidor. **No hace falta correr `db pull`**: los archivos se verificaron
uno por uno contra el arreglo `statements` que Supabase guardó al aplicarlas, y las 12
coinciden carácter por carácter. Reconstruyen el esquema exacto que está en producción.

Para conectar el CLI (solo si vas a hacer cambios al esquema desde ahora):

```bash
npx supabase init          # genera config.toml · responde N a lo de Deno/VS Code
npx supabase login         # abre el navegador
npx supabase link --project-ref ckvogrrzhdfdubqcwayn
npx supabase migration list   # local y remoto deben aparecer alineados
```

`link` pide la contraseña de la base. Si no la recuerdas, se reinicia en el panel:
Project Settings → Database → Reset database password.

De ahí en adelante: `npx supabase migration new <nombre>` para crear una, y
`npx supabase db push` para aplicarla.

## Migraciones aplicadas

| # | Migración | Qué hace |
|---|---|---|
| 01 | `profiles_and_helpers` | Perfil de usuario, trigger de alta automática, consentimiento de investigación |
| 02 | `exercise_catalog_and_routines` | Catálogo de ejercicios con IDs, plantillas de rutina |
| 03 | `workouts_and_sets` | Sesiones y series. **Aquí vive el campo `rir`** |
| 04 | `body_nutrition_sleep_swims_plan` | Peso, medidas, sueño, natación, **nutrición** y curva del plan |
| 05 | `ml_models_and_predictions` | Versionado de modelos y bitácora de predicciones |
| 06 | `analytics_and_ml_views` | Vistas analíticas y `v_ml_dataset` |
| 07 | `row_level_security` | RLS en las 14 tablas |
| 08 | `seed_global_catalog` | 29 ejercicios y 5 rutinas migrados desde `index.html` |
| 09 | `harden_functions` | `search_path` fijo y `EXECUTE` revocado en funciones de trigger |
| 10 | `fk_indexes_and_policy_split` | Índices de llaves foráneas, políticas separadas por acción |
| 11 | `client_uid_for_offline_sync` | `client_uid` en `workouts` y `swims` para sincronización idempotente |
| 12 | `client_uid_not_null_unique` | Corrección: restricción única plena (la parcial rompía el `upsert` del cliente) |
| 13 | `onboarding_fields_and_fullbody_routines` | Campos de alta en `profiles` y 3 rutinas de cuerpo completo para quien entrena 3 días |

Verificado con el linter de Supabase: **0 avisos de seguridad**.

## Pruebas ejecutadas

Se probó bajo el rol `authenticated` con un JWT de usuario real, es decir
**atravesando las políticas RLS**, no como superusuario:

- Alta de perfil por trigger al registrarse ✓
- `upsert` por llave natural (fecha) en peso, medidas, sueño y nutrición ✓
- `upsert` por `client_uid` en sesiones y natación · reenviar no duplica ✓
- Inserción de series con RIR, incluyendo RIR nulo ✓
- Columnas generadas: `volume_kg` = 480 y `e1rm_kg` = 76.0 para 60 kg × 8 ✓
- `v_ml_dataset` legible con RLS, con rezagos, objetivo y variables nutricionales ✓
- `avg_rir` ignora los nulos (3 series, 2 con RIR → promedio 1.5) ✓
- Aislamiento: el usuario solo ve su propio perfil ✓

Los datos de prueba se eliminaron. El catálogo global quedó intacto.

## Reconstruir desde cero

Si el proyecto desapareciera, se levanta otro y se aplican las migraciones en orden:

```bash
npx supabase link --project-ref <nuevo-ref>
npx supabase db push
```

Sobre el proyecto actual, para borrar y rehacer:

```bash
npx supabase db reset --linked   # ⚠️ borra todos los datos
```

> El trigger `on_auth_user_created` vive en el esquema `auth`, que `db pull` no captura.
> Por eso conviene conservar estas migraciones escritas a mano en lugar de un volcado
> automático: la 01 sí lo incluye. El archivo `PEGAR_DESPUES_DEL_PULL.sql` solo hace
> falta si en algún momento regeneras el historial con `db pull`.

## Verificación rápida

```sql
select count(*) from exercises where owner_id is null;  -- 29
select count(*) from routines  where owner_id is null;  -- 5
select count(*) from v_ml_dataset;                      -- 0 hasta que haya sesiones
```
