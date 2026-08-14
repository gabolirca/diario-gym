-- =====================================================================
-- GymAI · 20 · Registro del modelo y caducidad de los datos de prueba
--
-- Dos cosas que van juntas porque las dos existen para lo mismo: que
-- nadie confunda una demostración con evidencia.
--
--   1. El modelo queda registrado con su versión y sus métricas. Cada
--      predicción apunta a la versión que la produjo, así que dentro de
--      seis meses todavía se podrá decir qué modelo dijo qué.
--   2. Los participantes inventados caducan solos. La marca is_demo ya
--      los separa del análisis, pero una marca depende de que alguien se
--      acuerde de filtrarla; una fecha de borrado no depende de nadie.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. El modelo que está en producción
-- ---------------------------------------------------------------------
insert into public.model_versions
  (version, model_kind, algorithm, trained_at, n_samples, n_users, metrics, feature_set, notes, is_active)
values (
  'carga-v1',
  'progresion',                       -- el catálogo de tipos ya existe desde la migración 05
  'RandomForestRegressor (40 árboles, profundidad 6, mínimo 20 por hoja)',
  now(),
  13088,
  160,
  jsonb_build_object(
    'mae_kg',                    0.908,
    'rmse_kg',                   1.926,
    'dentro_de_un_disco_pct',    93.6,
    'mae_usuarios_nuevos_kg',    0.953,
    'mejor_linea_base_kg',       1.768,
    'mejora_vs_linea_base_pct',  48.6,
    'particion',                 'temporal, último 25 % de cada serie',
    'lineas_base', jsonb_build_object(
        'persistencia_kg',        1.768,
        'progresion_lineal_kg',   3.394,
        'lineal_doble_por_rir_kg',1.788)
  ),
  jsonb_build_object(
    'objetivo',   'delta_kg',
    'n_variables', 51,
    'excluidas',  jsonb_build_array('days_to_next_session'),
    'fuente',     'v_ml_dataset'
  ),
  'Entrenado SOLO con datos sintéticos (160 usuarios simulados, 20 semanas). '
  'Todavía no ha visto un solo entrenamiento real: las métricas describen su '
  'comportamiento en simulación, no su utilidad clínica. Se sustituye en cuanto '
  'haya historial de participantes.',
  true
)
on conflict do nothing;

-- Solo un modelo activo a la vez, o las predicciones dejan de ser trazables
create unique index if not exists model_versions_uno_activo
  on public.model_versions (model_kind) where is_active;

-- ---------------------------------------------------------------------
-- 2. Los datos de prueba se borran solos
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists demo_expires_at timestamptz;

comment on column public.profiles.demo_expires_at is
  'Fecha a partir de la cual este participante inventado se elimina solo. Nulo en las cuentas reales.';

-- Que no se pueda poner fecha de caducidad a una cuenta real por accidente
alter table public.profiles drop constraint if exists profiles_caducidad_solo_demo;
alter table public.profiles add constraint profiles_caducidad_solo_demo
  check (demo_expires_at is null or is_demo);

create or replace function private.borrar_demos_caducados()
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare n integer;
begin
  -- Borrar la cuenta arrastra en cascada sesiones, pesos, comida y escaneos.
  with fuera as (
    delete from auth.users u
     using public.profiles p
     where p.id = u.id
       and p.is_demo
       and p.demo_expires_at is not null
       and p.demo_expires_at <= now()
    returning u.id
  )
  select count(*) into n from fuera;
  return n;
end;
$$;

revoke all on function private.borrar_demos_caducados() from public, anon, authenticated;

comment on function private.borrar_demos_caducados() is
  'Elimina los participantes inventados cuya fecha de caducidad ya pasó. La ejecuta pg_cron todos los días.';

-- ---------------------------------------------------------------------
-- 3. Programarlo
-- ---------------------------------------------------------------------
create extension if not exists pg_cron;

select cron.unschedule('borrar-demos-caducados')
 where exists (select 1 from cron.job where jobname = 'borrar-demos-caducados');

select cron.schedule('borrar-demos-caducados', '17 4 * * *',
                     $$select private.borrar_demos_caducados()$$);

-- ---------------------------------------------------------------------
-- 4. Qué tan bien predice el modelo, ya con datos reales
--
-- close_prediction_loop (migración 05) rellena error_kg cuando la persona
-- registra la sesión. Esta vista lo resume, separando lo inventado de lo
-- real: mezclarlos daría un número bonito y falso.
-- ---------------------------------------------------------------------
create or replace view public.v_error_modelo as
select
  mv.version                                              as modelo,
  coalesce(p.is_demo, false)                              as es_demo,
  count(*)                                                as predicciones,
  count(pr.error_kg)                                      as ya_comprobadas,
  round(avg(abs(pr.error_kg)), 3)                         as mae_kg,
  round(avg(pr.error_kg), 3)                              as sesgo_kg,
  round(avg((abs(pr.error_kg) <= 2.5)::int) * 100, 1)     as dentro_de_un_disco_pct,
  round(avg((pr.clamped)::int) * 100, 1)                  as pct_recortadas
from public.predictions pr
join public.profiles p       on p.id = pr.user_id
left join public.model_versions mv on mv.id = pr.model_version_id
group by mv.version, coalesce(p.is_demo, false);

alter view public.v_error_modelo set (security_invoker = on);

comment on view public.v_error_modelo is
  'Error del modelo contra lo que la persona levantó de verdad. Separado por es_demo: los participantes inventados no pueden contar como evidencia.';
