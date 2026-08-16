-- =====================================================================
-- GymAI · 21 · Comidas por tiempo del día · Natación en el panel
--
-- Dos cosas sin relación entre sí, en la misma migración porque salen de
-- la misma sesión de trabajo.
--
-- 1. COMIDAS. Hasta ahora el día era una sola fila: capturabas el total y
--    ya. Registrar desayuno, comida y cena por separado —cada una con su
--    foto— es más rápido y más fiel a cómo come la gente, que no suma sus
--    calorías a las once de la noche.
--
--    Lo importante para el estudio es que **cada comida guarda su propio
--    origen**. Un día puede tener el desayuno capturado a mano y la cena
--    estimada por una foto, y eso no es ni un día medido ni un día
--    adivinado: es una mezcla. En vez de forzar una etiqueta, se guarda
--    la proporción exacta y el análisis decide después dónde poner el
--    umbral.
--
-- 2. NATACIÓN. El panel del investigador solo mira pesas. Quien nada
--    tiene una métrica de condición mucho más limpia que el tonelaje: el
--    ritmo por 100 m en series de intervalos. Si en el mes 3 nadas los
--    mismos 100 m más rápido con el mismo descanso, mejoraste, aunque la
--    báscula no se haya movido.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Cada comida, con su origen
-- ---------------------------------------------------------------------
create table public.meal_entries (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  client_uid  text not null,                       -- generado en el dispositivo
  logged_on   date not null,
  meal        text not null check (meal in ('desayuno','comida','cena')),

  kcal        integer      check (kcal      between 0 and 8000),
  protein_g   numeric(6,1) check (protein_g between 0 and 400),
  carbs_g     numeric(6,1) check (carbs_g   between 0 and 1000),
  fat_g       numeric(6,1) check (fat_g     between 0 and 400),

  -- De dónde salió ESTA comida, no el día entero
  source      text not null default 'manual' check (source in ('manual','photo_ai')),
  scan_id     bigint references public.food_scans(id) on delete set null,
  items       jsonb,                               -- qué alimentos reconoció el modelo
  notes       text,
  created_at  timestamptz not null default now(),

  unique (user_id, client_uid)
);

create index meal_entries_user_date_idx on public.meal_entries (user_id, logged_on desc);

comment on table public.meal_entries is
  'Una fila por comida registrada (desayuno, comida o cena). Puede haber varias del mismo tiempo el mismo día. El total diario sigue viviendo en nutrition_logs; esta tabla guarda el desglose y, sobre todo, de dónde salió cada parte.';
comment on column public.meal_entries.source is
  'manual = lo capturó la persona · photo_ai = lo estimó el modelo desde una foto. La foto nunca se guarda.';

alter table public.meal_entries enable row level security;

create policy meal_entries_select on public.meal_entries
  for select to authenticated
  using ((select auth.uid()) = user_id or private.es_admin());
create policy meal_entries_insert on public.meal_entries
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy meal_entries_update on public.meal_entries
  for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy meal_entries_delete on public.meal_entries
  for delete to authenticated using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------
-- 2. Qué parte del día vino de una foto
--
-- Se guarda el número exacto en vez de una etiqueta. Así el análisis
-- puede decidir su propio umbral —"solo días con menos del 20 % estimado"—
-- sin que esa decisión quede congelada aquí.
-- ---------------------------------------------------------------------
alter table public.nutrition_logs
  add column if not exists pct_estimado numeric(5,1)
  check (pct_estimado is null or pct_estimado between 0 and 100);

comment on column public.nutrition_logs.pct_estimado is
  'Porcentaje de las kcal del día que salió de una estimación por foto. 0 = todo capturado a mano, 100 = todo estimado, nulo = día anterior a esta función.';

-- 'mixto' para los días que combinan captura y estimación
alter table public.nutrition_logs drop constraint if exists nutrition_logs_source_check;
alter table public.nutrition_logs add constraint nutrition_logs_source_check
  check (source in ('manual','estimated','imported','photo_ai','mixto'));

comment on column public.nutrition_logs.source is
  'manual = lo capturó la persona · estimated = derivado del plan · imported = respaldo · photo_ai = todo estimado por foto · mixto = una parte de cada. Solo manual cuenta como evidencia sin reservas; pct_estimado da el detalle.';

-- ---------------------------------------------------------------------
-- 3. El desglose del día, listo para consultar
-- ---------------------------------------------------------------------
create or replace view public.v_comidas_del_dia as
select
  user_id, logged_on,
  count(*)                                                  as registros,
  sum(kcal)                                                 as kcal,
  sum(protein_g)                                            as protein_g,
  sum(carbs_g)                                              as carbs_g,
  sum(fat_g)                                                as fat_g,
  sum(kcal) filter (where source = 'photo_ai')              as kcal_de_foto,
  round(100.0 * coalesce(sum(kcal) filter (where source = 'photo_ai'), 0)
        / nullif(sum(kcal), 0), 1)                          as pct_estimado,
  jsonb_object_agg(meal, kcal_tiempo)                       as por_tiempo
from (
  select user_id, logged_on, meal, source, kcal, protein_g, carbs_g, fat_g,
         sum(kcal) over (partition by user_id, logged_on, meal) as kcal_tiempo
  from public.meal_entries
) m
group by user_id, logged_on;

alter view public.v_comidas_del_dia set (security_invoker = on);

comment on view public.v_comidas_del_dia is
  'Suma de las comidas de cada día con la proporción que vino de fotos. Es lo que alimenta el botón de sumar el día en la app.';

-- ---------------------------------------------------------------------
-- 4. Natación en el panel del investigador
--
-- La métrica es el ritmo por 100 m en las series de INTERVALOS. Los nados
-- continuos y los de técnica no son comparables entre sí: mezclarlos daría
-- una curva que sube y baja por el tipo de sesión, no por la condición.
--
-- Solo aparece quien tiene nados registrados: los participantes que no
-- activaron esa parte no ensucian la tabla.
-- ---------------------------------------------------------------------
create or replace view public.v_admin_natacion as
with base as (
  select p.id, p.display_name, p.is_demo,
         row_number() over (order by p.created_at) as n
  from public.profiles p where not p.is_admin
),
intervalos as (
  select user_id, performed_on, pace_sec_100m,
         row_number() over (partition by user_id order by performed_on)      as asc_n,
         row_number() over (partition by user_id order by performed_on desc) as desc_n
  from public.swims
  where kind = 'intervalos' and pace_sec_100m is not null
)
select
  b.id                                        as user_id,
  'P' || lpad(b.n::text, 2, '0')              as codigo,
  b.display_name                              as nombre,
  b.is_demo                                   as es_demo,
  s.sesiones,
  s.metros_total,
  s.minutos_total,
  s.primera_fecha,
  s.ultima_fecha,
  (current_date - s.ultima_fecha)             as dias_sin_nadar,
  pi.pace_sec_100m                            as ritmo_inicial_seg,
  pf.pace_sec_100m                            as ritmo_actual_seg,
  -- Negativo = va más rápido = mejoró. Se deja el signo crudo a propósito:
  -- invertirlo para que "más es mejor" se presta a confusión al leerlo.
  (pf.pace_sec_100m - pi.pace_sec_100m)       as cambio_seg,
  case when pi.pace_sec_100m > 0
       then round(100.0 * (pf.pace_sec_100m - pi.pace_sec_100m) / pi.pace_sec_100m, 1)
  end                                         as cambio_pct,
  s.sesiones_intervalos
from base b
join lateral (
  select count(*)                                                as sesiones,
         sum(meters)                                             as metros_total,
         sum(minutes)                                            as minutos_total,
         min(performed_on)                                       as primera_fecha,
         max(performed_on)                                       as ultima_fecha,
         count(*) filter (where kind = 'intervalos')             as sesiones_intervalos
  from public.swims w where w.user_id = b.id
) s on s.sesiones > 0                       -- solo quien nada
left join intervalos pi on pi.user_id = b.id and pi.asc_n  = 1
left join intervalos pf on pf.user_id = b.id and pf.desc_n = 1;

alter view public.v_admin_natacion set (security_invoker = on);

comment on view public.v_admin_natacion is
  'Seguimiento de natación. Solo incluye a quien tiene nados registrados. El ritmo se toma solo de las series de intervalos, que son las comparables entre sí. cambio_seg negativo significa que va más rápido.';
