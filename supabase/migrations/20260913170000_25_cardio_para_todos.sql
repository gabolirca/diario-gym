-- =====================================================================
-- GymAI · 25 · Cardio en todos los programas
--
-- El cardio ya existía, pero solo en el programa «Glúteo y cintura».
-- Fuera de ahí no aparecía escrito en ninguna parte, que es justamente
-- la razón por la que se salta. Ahora cierra todos los días de fuerza.
--
-- NO CAMBIA NINGÚN CÁLCULO. Es la misma fila que v_working_sets ya
-- descarta por exercises.kind = 'cardio' (migración 24): no suma
-- tonelaje, no aparece en récords, no entra al conjunto de
-- entrenamiento del modelo ni a las predicciones. Lo único que se hace
-- con ella es contar cuántas veces por semana se registró, y eso se
-- calcula en la app y en el panel, no aquí.
--
-- El sábado de acondicionamiento se queda sin cardio: esa sesión ya es
-- entera de ese tipo, ponerle veinte minutos más al final sería contar
-- lo mismo dos veces.
-- =====================================================================

insert into public.routine_exercises (routine_id, exercise_id, order_index, target_sets,
                                      target_reps_min, target_reps_max,
                                      target_rir_min, target_rir_max)
select r.id,
       c.id,
       coalesce(max(re.order_index), 0) + 1,
       1,
       15, 15,          -- minutos, no repeticiones: el campo se reusa
       2, 3             -- sin significado real; la columna es NOT NULL
from public.routines r
cross join lateral (
  select e.id from public.exercises e where e.slug = 'cardio' and e.owner_id is null
) c
left join public.routine_exercises re on re.routine_id = r.id
where r.owner_id is null
  and coalesce(r.kind, 'fuerza') <> 'acondicionamiento'
  and not exists (
    select 1 from public.routine_exercises x
    where x.routine_id = r.id and x.exercise_id = c.id
  )
group by r.id, c.id
on conflict (routine_id, order_index) do nothing;

comment on table public.routine_exercises is
  'Definición de cada día del catálogo. El último renglón de cada rutina de fuerza es cardio: se captura en minutos en el campo de repeticiones y queda fuera de v_working_sets, así que sirve para medir constancia y para nada más.';

-- ---------------------------------------------------------------------
-- La fuga: cuatro vistas leían workout_sets en crudo
--
-- v_working_sets es el punto único donde se decide qué es una serie de
-- trabajo, pero cuatro vistas se saltaban ese filtro y leían la tabla
-- directamente. Mientras el cardio solo existía en un programa daba casi
-- igual; ahora que está en todos los días, cada una habría quedado mal:
--
--   · v_admin_progreso     · avg(e1rm_kg) con filas de 0 kg hunde el
--                            promedio de fuerza de toda la semana.
--   · v_admin_participantes· series cuenta el cardio pero series_con_rir
--                            no (el cardio no lleva RIR), así que pct_rir
--                            —la métrica de calidad del registro del
--                            estudio— bajaba sola sin que nadie
--                            registrara peor.
--   · v_weekly_volume      · tonelaje sin cambio, pero sessions sí.
--   · v_session_score      · es el gemelo en SQL de calificar() en la
--                            app; si uno excluye el cardio y el otro no,
--                            el panel y el teléfono dan notas distintas
--                            para la misma sesión.
--
-- Las cuatro pasan a leer v_working_sets. De paso heredan el filtro de
-- acondicionamiento, que es lo que la app ya hacía por su lado.
-- ---------------------------------------------------------------------
create or replace view public.v_weekly_volume as
select vws.user_id,
       (date_trunc('week', vws.performed_on::timestamptz))::date as week_start,
       round(sum(vws.volume_kg) / 1000.0, 2) as tonnage_t,
       count(distinct vws.workout_id) as sessions
from public.v_working_sets vws
group by vws.user_id, date_trunc('week', vws.performed_on::timestamptz);

alter view public.v_weekly_volume set (security_invoker = on);

create or replace view public.v_admin_progreso as
select vws.user_id,
       greatest(1, (floor((vws.performed_on - p.plan_start)::numeric / 7.0))::integer + 1) as semana,
       count(distinct vws.workout_id) as sesiones,
       round(sum(vws.volume_kg) / 1000.0, 2) as tonelaje_t,
       round(avg(vws.e1rm_kg), 1) as e1rm_promedio,
       round(avg(vws.rir), 2) as rir_promedio,
       count(vws.set_id) as series,
       count(vws.rir) as series_con_rir
from public.v_working_sets vws
join public.profiles p on p.id = vws.user_id
where p.plan_start is not null
group by vws.user_id,
         greatest(1, (floor((vws.performed_on - p.plan_start)::numeric / 7.0))::integer + 1);

alter view public.v_admin_progreso set (security_invoker = on);

-- drop + create y no create or replace: replace exige que las columnas
-- salgan idénticas, y no vale la pena que la migración dependa de eso.
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
select b.id as user_id,
       'P' || lpad(b.n::text, 2, '0') as codigo,
       b.display_name as nombre,
       b.sex, b.goal,
       b.is_demo as es_demo,
       b.training_days_per_week as dias_semana,
       b.research_consent as consiente,
       (b.onboarded_at is not null) as dado_de_alta,
       b.plan_start, b.plan_weeks, b.initial_weight_kg, b.target_weight_kg,
       b.created_at as alta_en,
       coalesce(w.sesiones, 0) as sesiones,
       w.ultima_sesion,
       case when w.ultima_sesion is not null then current_date - w.ultima_sesion end as dias_sin_entrenar,
       coalesce(w.series, 0) as series,
       coalesce(w.series_con_rir, 0) as series_con_rir,
       case when coalesce(w.series, 0) > 0
            then round(w.series_con_rir::numeric / w.series::numeric * 100, 0) end as pct_rir,
       coalesce(pe.dias_peso, 0) as dias_peso,
       pe.ultimo_peso,
       coalesce(nu.dias_comida, 0) as dias_comida,
       case when b.plan_start is not null
            then greatest(1, (floor((current_date - b.plan_start)::numeric / 7.0))::integer + 1) end as semana_actual
from base b
-- sesiones se cuenta sobre workouts, no sobre las series: un día que se
-- registró sin capturar nada sigue siendo un día que fue al gimnasio.
left join lateral (
  select count(distinct wo.id) as sesiones,
         max(wo.performed_on) as ultima_sesion,
         count(vws.set_id) as series,
         count(vws.rir) as series_con_rir
  from public.workouts wo
  left join public.v_working_sets vws on vws.workout_id = wo.id
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
  from public.nutrition_logs n
  where n.user_id = b.id and n.source = 'manual'
) nu on true;

alter view public.v_admin_participantes set (security_invoker = on);

create or replace view public.v_session_score as
with series as (
  select vws.workout_id, vws.user_id, vws.performed_on, w.routine_id,
         vws.exercise_id, vws.rir, vws.e1rm_kg, vws.volume_kg,
         coalesce(re.target_rir_min, 1) as rir_min,
         coalesce(re.target_rir_max, 3) as rir_max
  from public.v_working_sets vws
  join public.workouts w on w.id = vws.workout_id
  left join public.routine_exercises re
         on re.routine_id = w.routine_id and re.exercise_id = vws.exercise_id
), por_sesion as (
  select workout_id, user_id, performed_on, routine_id,
         count(*) as series,
         count(rir) as series_con_rir,
         count(*) filter (where rir >= rir_min and rir <= rir_max) as series_en_ventana,
         round(avg(e1rm_kg), 2) as e1rm_medio,
         round(sum(volume_kg), 1) as volumen
  from series
  group by workout_id, user_id, performed_on, routine_id
), con_previa as (
  select s.*,
         lag(s.e1rm_medio) over (partition by s.user_id order by s.performed_on) as e1rm_previo,
         lag(s.performed_on) over (partition by s.user_id order by s.performed_on) as sesion_previa,
         p.training_days_per_week
  from por_sesion s
  join public.profiles p on p.id = s.user_id
)
select workout_id, user_id, performed_on, series, series_con_rir, series_en_ventana,
       e1rm_medio, e1rm_previo, volumen,
       (performed_on - sesion_previa) as dias_desde_previa,
       round(case when series_con_rir > 0
                  then series_en_ventana::numeric / series_con_rir::numeric
                  else 0.5 end * 40, 1) as p_esfuerzo,
       round(case when e1rm_previo is null or e1rm_previo = 0 then 0.70
                  when e1rm_medio >= e1rm_previo * 1.02 then 1.00
                  when e1rm_medio >= e1rm_previo then 0.85
                  when e1rm_medio >= e1rm_previo * 0.95 then 0.60
                  else 0.30 end * 25, 1) as p_progresion,
       round(case when series > 0
                  then series_con_rir::numeric / series::numeric
                  else 0 end * 20, 1) as p_registro,
       round(case when sesion_previa is null then 0.75
                  when (performed_on - sesion_previa)::numeric
                       <= ceil(7.0 / greatest(training_days_per_week, 1)::numeric) + 1 then 1.00
                  when (performed_on - sesion_previa) <= 7 then 0.70
                  when (performed_on - sesion_previa) <= 14 then 0.40
                  else 0.15 end * 15, 1) as p_constancia
from con_previa;

alter view public.v_session_score set (security_invoker = on);

comment on view public.v_session_score is
  'Gemelo en SQL de calificar() en la app: las dos tienen que dar el mismo número para la misma sesión. Lee v_working_sets, así que no ve calentamiento, ni acondicionamiento, ni cardio — igual que la app.';
