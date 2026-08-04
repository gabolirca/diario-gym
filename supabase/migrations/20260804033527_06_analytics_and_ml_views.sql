-- =====================================================================
-- GymAI · 06 · Vistas analíticas y dataset de entrenamiento
-- =====================================================================

-- Porcentaje de grasa por fórmula Navy (requiere altura del perfil,
-- por eso es vista y no columna generada).
create or replace view public.v_body_fat as
select
  m.user_id,
  m.measured_on,
  m.waist_cm,
  m.neck_cm,
  p.height_cm,
  case
    when m.waist_cm is not null and m.neck_cm is not null
     and p.height_cm is not null and m.waist_cm > m.neck_cm
    then round(
      (495 / (1.0324 - 0.19077 * log(10, (m.waist_cm - m.neck_cm)::numeric)
                     + 0.15456 * log(10, p.height_cm::numeric)) - 450)::numeric, 1)
  end as body_fat_pct
from public.body_measures m
join public.profiles p on p.id = m.user_id;

-- ---------------------------------------------------------------------
-- Series efectivas (sin calentamiento), aplanadas con usuario y fecha
create or replace view public.v_working_sets as
select
  ws.id            as set_id,
  w.user_id,
  w.id             as workout_id,
  w.performed_on,
  ws.exercise_id,
  ws.set_index,
  ws.weight_kg,
  ws.reps,
  ws.rir,
  ws.to_failure,
  ws.volume_kg,
  ws.e1rm_kg
from public.workout_sets ws
join public.workouts w on w.id = ws.workout_id
where not ws.is_warmup;

-- ---------------------------------------------------------------------
-- Una fila por usuario × ejercicio × sesión
create or replace view public.v_exercise_sessions as
select
  user_id,
  exercise_id,
  performed_on,
  count(*)                       as n_sets,
  max(weight_kg)                 as top_weight_kg,
  max(e1rm_kg)                   as top_e1rm_kg,
  sum(volume_kg)                 as total_volume_kg,
  round(avg(reps)::numeric, 1)   as avg_reps,
  round(avg(rir)::numeric, 2)    as avg_rir,
  min(rir)                       as min_rir,
  bool_or(to_failure)            as any_failure,
  count(rir)                     as n_sets_with_rir
from public.v_working_sets
group by user_id, exercise_id, performed_on;

-- ---------------------------------------------------------------------
-- DATASET DE ENTRENAMIENTO DEL MODELO B (progresión)
-- Una fila por sesión, con rezagos y contexto. El objetivo (target) es
-- la carga máxima de la SIGUIENTE sesión del mismo ejercicio.
-- ---------------------------------------------------------------------
create or replace view public.v_ml_dataset as
with s as (
  select
    es.*,
    row_number() over (partition by es.user_id, es.exercise_id order by es.performed_on) as session_no,

    lag(es.top_weight_kg,   1) over hist as prev1_weight_kg,
    lag(es.top_weight_kg,   2) over hist as prev2_weight_kg,
    lag(es.top_weight_kg,   3) over hist as prev3_weight_kg,
    lag(es.avg_rir,         1) over hist as prev1_avg_rir,
    lag(es.avg_rir,         2) over hist as prev2_avg_rir,
    lag(es.total_volume_kg, 1) over hist as prev1_volume_kg,
    lag(es.top_e1rm_kg,     1) over hist as prev1_e1rm_kg,
    lag(es.performed_on,    1) over hist as prev_session_on,

    -- OBJETIVO
    lead(es.top_weight_kg, 1) over hist as target_next_weight_kg,
    lead(es.performed_on,  1) over hist as next_session_on
  from public.v_exercise_sessions es
  window hist as (partition by es.user_id, es.exercise_id order by es.performed_on)
)
select
  s.user_id,
  s.exercise_id,
  s.performed_on,
  s.session_no,

  -- Perfil
  p.sex,
  p.research_consent,
  case when p.birth_date is not null
       then round(extract(epoch from age(s.performed_on, p.birth_date)) / 31557600.0, 1) end as age_years,
  p.height_cm,
  case when p.training_since is not null
       then round(extract(epoch from age(s.performed_on, p.training_since)) / 2629800.0, 1) end as experience_months,
  p.goal,

  -- Ejercicio
  e.muscle_group,
  e.movement_pattern,
  e.equipment,
  e.is_compound,
  e.load_increment_kg,

  -- Desempeño actual
  s.top_weight_kg,
  s.top_e1rm_kg,
  s.total_volume_kg,
  s.avg_reps,
  s.avg_rir,
  s.min_rir,
  s.n_sets,
  s.n_sets_with_rir,
  s.any_failure,

  -- Rezagos
  s.prev1_weight_kg,
  s.prev2_weight_kg,
  s.prev3_weight_kg,
  s.prev1_avg_rir,
  s.prev2_avg_rir,
  s.prev1_volume_kg,
  s.prev1_e1rm_kg,
  (s.performed_on - s.prev_session_on)              as days_since_prev_session,
  case when s.prev1_weight_kg > 0
       then round((s.top_weight_kg - s.prev1_weight_kg) / s.prev1_weight_kg * 100, 2) end as pct_change_vs_prev,

  -- Recuperación
  (s.next_session_on - s.performed_on)              as days_to_next_session,
  sl.sleep_h_7d,

  -- Peso corporal (promedio 7 días previos)
  bw.bodyweight_7d_kg,

  -- NUTRICIÓN (7 días previos) — variables de la hipótesis H2
  nu.kcal_7d,
  nu.kcal_target_7d,
  (nu.kcal_7d - nu.kcal_target_7d)                  as kcal_balance_7d,
  nu.protein_7d,
  case when bw.bodyweight_7d_kg > 0
       then round((nu.protein_7d / bw.bodyweight_7d_kg)::numeric, 2) end as protein_g_per_kg_7d,
  nu.days_logged_7d,

  -- OBJETIVO
  s.target_next_weight_kg,
  case when s.target_next_weight_kg is not null
       then s.target_next_weight_kg - s.top_weight_kg end as target_delta_kg

from s
join public.profiles  p on p.id = s.user_id
join public.exercises e on e.id = s.exercise_id

left join lateral (
  select round(avg(n.kcal)::numeric, 0)        as kcal_7d,
         round(avg(n.kcal_target)::numeric, 0) as kcal_target_7d,
         round(avg(n.protein_g)::numeric, 1)   as protein_7d,
         count(*)                              as days_logged_7d
  from public.nutrition_logs n
  where n.user_id = s.user_id
    and n.source  = 'manual'
    and n.logged_on between s.performed_on - 7 and s.performed_on - 1
) nu on true

left join lateral (
  select round(avg(b.weight_kg)::numeric, 2) as bodyweight_7d_kg
  from public.body_weights b
  where b.user_id = s.user_id
    and b.measured_on between s.performed_on - 7 and s.performed_on
) bw on true

left join lateral (
  select round(avg(x.hours)::numeric, 2) as sleep_h_7d
  from public.sleep_logs x
  where x.user_id = s.user_id
    and x.logged_on between s.performed_on - 7 and s.performed_on - 1
) sl on true;

comment on view public.v_ml_dataset is
  'Dataset listo para entrenar el modelo de progresión. Filtrar por research_consent = true y target_next_weight_kg is not null. Los rezagos ya vienen calculados: no hay fuga temporal porque solo se usa información anterior o de la propia sesión.';

-- ---------------------------------------------------------------------
-- Volumen semanal (equivale a la gráfica chVol del index.html)
create or replace view public.v_weekly_volume as
select
  w.user_id,
  date_trunc('week', w.performed_on)::date as week_start,
  round(sum(ws.volume_kg) / 1000.0, 2)     as tonnage_t,
  count(distinct w.id)                     as sessions
from public.workouts w
join public.workout_sets ws on ws.workout_id = w.id and not ws.is_warmup
group by w.user_id, date_trunc('week', w.performed_on);

-- Récords personales (equivale a la tabla prTable)
create or replace view public.v_personal_records as
select distinct on (user_id, exercise_id)
  user_id, exercise_id, performed_on as achieved_on, top_weight_kg, top_e1rm_kg
from public.v_exercise_sessions
order by user_id, exercise_id, top_e1rm_kg desc, performed_on desc;
