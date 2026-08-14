-- =====================================================================
-- GymAI · 18 · Calificación del entrenamiento
--
-- Califica cada sesión de 0 a 100 con lo que ya se registra. Ninguna
-- componente inventa nada: todas salen de peso, repeticiones y RIR.
--
--   Esfuerzo      40 %  ¿el RIR cayó en la ventana objetivo del ejercicio?
--   Progresión    25 %  1RM estimado contra la sesión anterior
--   Registro      20 %  proporción de series con RIR reportado
--   Constancia    15 %  días transcurridos contra los que tocaban
--
-- Los pesos están aquí y en el cliente. Si se cambian, hay que cambiarlos
-- en los dos lados: la app tiene que poder calificar sin conexión.
-- =====================================================================

create or replace view public.v_session_score as
with series as (
  select w.id as workout_id, w.user_id, w.performed_on, w.routine_id,
         ws.exercise_id, ws.rir, ws.e1rm_kg, ws.volume_kg,
         -- Ventana objetivo del ejercicio en esa rutina; si no está
         -- definida se usa la de referencia (1 a 3).
         coalesce(re.target_rir_min, 1) as rir_min,
         coalesce(re.target_rir_max, 3) as rir_max
  from public.workouts w
  join public.workout_sets ws on ws.workout_id = w.id and not ws.is_warmup
  left join public.routine_exercises re
         on re.routine_id = w.routine_id and re.exercise_id = ws.exercise_id
),
por_sesion as (
  select workout_id, user_id, performed_on, routine_id,
         count(*)                                                as series,
         count(rir)                                              as series_con_rir,
         count(*) filter (where rir between rir_min and rir_max)  as series_en_ventana,
         round(avg(e1rm_kg), 2)                                  as e1rm_medio,
         round(sum(volume_kg), 1)                                as volumen
  from series group by workout_id, user_id, performed_on, routine_id
),
con_previa as (
  select s.*,
         lag(s.e1rm_medio)   over (partition by s.user_id order by s.performed_on) as e1rm_previo,
         lag(s.performed_on) over (partition by s.user_id order by s.performed_on) as sesion_previa,
         p.training_days_per_week
  from por_sesion s
  join public.profiles p on p.id = s.user_id
)
select
  workout_id, user_id, performed_on, series, series_con_rir, series_en_ventana,
  e1rm_medio, e1rm_previo, volumen,
  (performed_on - sesion_previa) as dias_desde_previa,

  -- 1. Esfuerzo: qué proporción de las series con RIR cayó en la ventana.
  --    Sin RIR no se puede juzgar: se otorga la mitad, ni premio ni castigo.
  round((case when series_con_rir > 0
              then series_en_ventana::numeric / series_con_rir else 0.5 end) * 40, 1) as p_esfuerzo,

  -- 2. Progresión: sostener ya vale la mayor parte; subir da el total.
  round((case
      when e1rm_previo is null or e1rm_previo = 0 then 0.70          -- primera sesión
      when e1rm_medio >= e1rm_previo * 1.02 then 1.00                -- +2 % o más
      when e1rm_medio >= e1rm_previo        then 0.85                -- sostiene
      when e1rm_medio >= e1rm_previo * 0.95 then 0.60                -- baja poco
      else 0.30 end) * 25, 1) as p_progresion,

  -- 3. Registro: proporción de series con RIR. Es lo que hace utilizable el dato.
  round((case when series > 0
              then series_con_rir::numeric / series else 0 end) * 20, 1) as p_registro,

  -- 4. Constancia: entrenar cuando toca, según su frecuencia declarada.
  round((case
      when sesion_previa is null then 0.75
      when (performed_on - sesion_previa) <= ceil(7.0 / greatest(training_days_per_week,1)) + 1 then 1.00
      when (performed_on - sesion_previa) <= 7  then 0.70
      when (performed_on - sesion_previa) <= 14 then 0.40
      else 0.15 end) * 15, 1) as p_constancia
from con_previa;

alter view public.v_session_score set (security_invoker = on);

comment on view public.v_session_score is
  'Calificación 0-100 por sesión. La suma de las cuatro componentes da el total.';

-- ---------------------------------------------------------------------
create or replace view public.v_session_score_total as
select *,
       round(p_esfuerzo + p_progresion + p_registro + p_constancia, 1) as calificacion
from public.v_session_score;

alter view public.v_session_score_total set (security_invoker = on);

create or replace view public.v_weekly_score as
select user_id,
       date_trunc('week', performed_on)::date as semana,
       count(*)                               as sesiones,
       round(avg(p_esfuerzo + p_progresion + p_registro + p_constancia), 1) as calificacion,
       round(avg(p_esfuerzo), 1)   as esfuerzo,
       round(avg(p_progresion), 1) as progresion,
       round(avg(p_registro), 1)   as registro,
       round(avg(p_constancia), 1) as constancia
from public.v_session_score
group by user_id, date_trunc('week', performed_on);

alter view public.v_weekly_score set (security_invoker = on);
