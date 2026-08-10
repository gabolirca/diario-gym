-- =====================================================================
-- GymAI · 17 · Marca de datos de demostración
--
-- Para enseñar el panel antes de tener participantes reales hacen falta
-- datos inventados. El riesgo es obvio: que alguien los tome por reales.
-- La marca vive en la base, no en el cliente, y el panel la muestra en
-- pantalla. Así nadie tiene que acordarse de aclararlo.
-- =====================================================================

alter table public.profiles add column is_demo boolean not null default false;

comment on column public.profiles.is_demo is
  'Participante inventado para demostración. Nunca debe entrar al análisis del estudio.';

-- Insertar una columna en medio obliga a recrear la vista, no basta REPLACE
drop view if exists public.v_admin_participantes;

create view public.v_admin_participantes as
with base as (
  select p.id, p.display_name, p.sex, p.goal, p.training_days_per_week,
         p.plan_start, p.plan_weeks, p.initial_weight_kg, p.target_weight_kg,
         p.research_consent, p.onboarded_at, p.created_at, p.is_demo,
         row_number() over (order by p.created_at) as n
  from public.profiles p
  where not p.is_admin
)
select
  b.id                                   as user_id,
  'P' || lpad(b.n::text, 2, '0')         as codigo,
  b.display_name                         as nombre,
  b.sex, b.goal,
  b.is_demo                              as es_demo,
  b.training_days_per_week               as dias_semana,
  b.research_consent                     as consiente,
  (b.onboarded_at is not null)           as dado_de_alta,
  b.plan_start, b.plan_weeks,
  b.initial_weight_kg, b.target_weight_kg,
  b.created_at                           as alta_en,

  coalesce(w.sesiones, 0)                as sesiones,
  w.ultima_sesion,
  case when w.ultima_sesion is not null
       then (current_date - w.ultima_sesion) end as dias_sin_entrenar,
  coalesce(w.series, 0)                  as series,
  coalesce(w.series_con_rir, 0)          as series_con_rir,
  case when coalesce(w.series,0) > 0
       then round(w.series_con_rir::numeric / w.series * 100, 0) end as pct_rir,

  coalesce(pe.dias_peso, 0)              as dias_peso,
  pe.ultimo_peso,
  coalesce(nu.dias_comida, 0)            as dias_comida,

  case when b.plan_start is not null
       then greatest(1, floor((current_date - b.plan_start)/7.0)::int + 1) end as semana_actual
from base b
left join lateral (
  select count(distinct wo.id) as sesiones, max(wo.performed_on) as ultima_sesion,
         count(ws.id) as series, count(ws.rir) as series_con_rir
  from public.workouts wo
  left join public.workout_sets ws on ws.workout_id = wo.id and not ws.is_warmup
  where wo.user_id = b.id
) w on true
left join lateral (
  select count(*) as dias_peso,
         (select bw.weight_kg from public.body_weights bw
           where bw.user_id = b.id order by bw.measured_on desc limit 1) as ultimo_peso
  from public.body_weights bw2 where bw2.user_id = b.id
) pe on true
left join lateral (
  select count(*) as dias_comida
  from public.nutrition_logs n where n.user_id = b.id and n.source = 'manual'
) nu on true;

alter view public.v_admin_participantes set (security_invoker = on);

comment on view public.v_admin_participantes is
  'Seguimiento del estudio. pct_rir es la métrica crítica. es_demo distingue a los participantes inventados.';
