-- =====================================================================
-- GymAI · 19 · Estimación de comida a partir de una foto
--
-- La foto NUNCA se guarda: ni en Storage, ni en una columna, ni en un
-- log. Viaja al modelo dentro de la petición y se descarta. Lo único que
-- queda en la base son números.
--
-- Se registra cada estimación por dos razones concretas:
--   1. Para poder medir el error del estimador. Guardando lo que dijo el
--      modelo y lo que el usuario terminó capturando, la diferencia es
--      medible. Sin esto, "la app estima calorías con IA" es una
--      afirmación sin evidencia.
--   2. Para limitar el uso diario por persona sin depender del cliente.
--
-- Un valor estimado por foto NO es un dato capturado. Por eso entra a
-- nutrition_logs con source='photo_ai' y no se mezcla con 'manual': las
-- vistas del estudio ya filtran por source, y la hipótesis H2 se sostiene
-- sobre lo que la persona midió, no sobre lo que un modelo adivinó.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Un origen más para el registro de ingesta
-- ---------------------------------------------------------------------
alter table public.nutrition_logs drop constraint if exists nutrition_logs_source_check;
alter table public.nutrition_logs add constraint nutrition_logs_source_check
  check (source in ('manual','estimated','imported','photo_ai'));

comment on column public.nutrition_logs.source is
  'manual = lo capturó la persona · estimated = derivado del plan · imported = respaldo · photo_ai = estimado por el modelo desde una foto. Solo manual cuenta como evidencia en el estudio.';

-- ---------------------------------------------------------------------
-- 2. Bitácora de estimaciones (sin imagen)
-- ---------------------------------------------------------------------
create table public.food_scans (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references public.profiles(id) on delete cascade,
  scanned_at     timestamptz not null default now(),

  -- Lo que dijo el modelo
  est_kcal       integer      check (est_kcal      between 0 and 12000),
  est_protein_g  numeric(6,1) check (est_protein_g between 0 and 600),
  est_carbs_g    numeric(6,1) check (est_carbs_g   between 0 and 1500),
  est_fat_g      numeric(6,1) check (est_fat_g     between 0 and 500),
  est_confidence text         check (est_confidence in ('alta','media','baja')),
  items          jsonb,                    -- qué alimentos creyó ver y en qué porción
  model          text not null,            -- versión exacta, para poder comparar entre modelos

  -- Qué hizo la persona con esa estimación. Se llena después, al guardar.
  accepted       boolean,
  final_kcal     integer      check (final_kcal between 0 and 12000),

  -- Diagnóstico. Nunca la imagen, solo su tamaño.
  image_bytes    integer      check (image_bytes between 0 and 20000000),
  ms             integer,                  -- cuánto tardó la llamada
  error          text                      -- si falló, por qué
);

create index food_scans_user_time_idx on public.food_scans (user_id, scanned_at desc);

comment on table public.food_scans is
  'Una fila por foto analizada. La imagen no se almacena en ningún momento. Guardar la estimación junto al valor que la persona terminó aceptando es lo que permite reportar el error del estimador en vez de solo afirmar que existe.';
comment on column public.food_scans.accepted is
  'true si la persona guardó el registro con los valores del modelo (ajustados o no). null mientras no decida.';
comment on column public.food_scans.final_kcal is
  'Kcal que quedaron guardadas. Contra est_kcal da el error real del estimador.';

-- ---------------------------------------------------------------------
-- 3. RLS: cada quien ve lo suyo, el investigador lee todo
-- ---------------------------------------------------------------------
alter table public.food_scans enable row level security;

create policy food_scans_select on public.food_scans
  for select to authenticated
  using ((select auth.uid()) = user_id or private.es_admin());

create policy food_scans_insert on public.food_scans
  for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy food_scans_update on public.food_scans
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy food_scans_delete on public.food_scans
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- 4. Cuánto lleva usado hoy esta persona
--
-- La cuota se comprueba en el servidor. Si viviera en el navegador,
-- bastaría con recargar la página para saltársela.
-- ---------------------------------------------------------------------
create or replace function private.fotos_hoy(uid uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)::int from public.food_scans
   where user_id = uid
     and scanned_at >= date_trunc('day', now());
$$;

revoke all on function private.fotos_hoy(uuid) from public, anon;

-- ---------------------------------------------------------------------
-- 5. Qué tan bien estima el modelo (para el panel y para el artículo)
-- ---------------------------------------------------------------------
create view public.v_error_estimador as
select
  count(*)                                                as estimaciones,
  count(*) filter (where accepted)                        as aceptadas,
  count(*) filter (where accepted is false)               as descartadas,
  round(avg(abs(final_kcal - est_kcal)), 1)               as mae_kcal,
  round(avg(final_kcal - est_kcal), 1)                    as sesgo_kcal,
  round(avg(abs(final_kcal - est_kcal)::numeric
            / nullif(final_kcal, 0)) * 100, 1)            as error_pct,
  round(avg(ms))                                          as ms_promedio
from public.food_scans
where final_kcal is not null and est_kcal is not null;

alter view public.v_error_estimador set (security_invoker = on);

comment on view public.v_error_estimador is
  'Error del estimador de comida medido contra lo que la persona terminó guardando. security_invoker: un participante solo ve sus propias filas, el investigador las de todos.';
