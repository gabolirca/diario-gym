-- =====================================================================
-- GymAI · Datos de DEMOSTRACIÓN
--
-- Participantes inventados para poder enseñar el panel antes de tener
-- datos reales. Todos quedan marcados con profiles.is_demo = true y el
-- panel lo anuncia en pantalla.
--
--   Ejecutar:  este archivo completo en el editor SQL de Supabase
--   Borrar:    ver demo_limpiar.sql
--
-- Cada participante está diseñado para disparar una alerta distinta:
--   Ana   · todo bien: 8 semanas, RIR completo, buena progresión
--   Beto  · registra peso y reps pero NUNCA el RIR
--   Caro  · dejó de entrenar hace 12 días
--   Dani  · completó el cuestionario pero no dio consentimiento
--   Eva   · creó cuenta y nunca hizo el cuestionario
-- =====================================================================

-- ---------- 1. Cuentas ----------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_app_meta_data, raw_user_meta_data)
values
 ('00000000-0000-4dee-9000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ana@demo.local', 'demo', now(), now()-interval '58 day', now(),'{}','{}'),
 ('00000000-0000-4dee-9000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','beto@demo.local','demo', now(), now()-interval '57 day', now(),'{}','{}'),
 ('00000000-0000-4dee-9000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','caro@demo.local','demo', now(), now()-interval '56 day', now(),'{}','{}'),
 ('00000000-0000-4dee-9000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','dani@demo.local','demo', now(), now()-interval '40 day', now(),'{}','{}'),
 ('00000000-0000-4dee-9000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','eva@demo.local', 'demo', now(), now()-interval '9 day',  now(),'{}','{}')
on conflict (id) do nothing;

-- ---------- 2. Perfiles ----------
update public.profiles p set
  is_demo = true,
  display_name = v.nombre, sex = v.sexo, birth_date = v.nace,
  height_cm = v.estatura, goal = v.objetivo,
  plan_start = current_date - v.dias_activo, plan_weeks = 18,
  initial_weight_kg = v.w0, target_weight_kg = v.meta,
  training_days_per_week = v.dias, training_since = current_date - (v.exp_meses * 30),
  research_consent = v.consiente,
  onboarded_at = case when v.hizo_alta then now() - (v.dias_activo || ' day')::interval end
from (values
  ('00000000-0000-4dee-9000-000000000001'::uuid,'DEMO · Ana', 'F','2001-03-14',163,'fat_loss',   66.0,60.0,3,20,true, true, 56),
  ('00000000-0000-4dee-9000-000000000002'::uuid,'DEMO · Beto','M','1998-07-02',178,'muscle_gain',74.0,80.0,4,30,true, true, 55),
  ('00000000-0000-4dee-9000-000000000003'::uuid,'DEMO · Caro','F','2003-11-25',158,'recomp',     61.0,57.0,3,8, true, true, 54),
  ('00000000-0000-4dee-9000-000000000004'::uuid,'DEMO · Dani','M','1996-01-09',181,'recomp',     88.0,82.0,5,60,false,true, 38),
  ('00000000-0000-4dee-9000-000000000005'::uuid,'DEMO · Eva', 'F','2004-05-30',167,'recomp',     70.0,66.0,3,4, false,false,7)
) as v(id,nombre,sexo,nace,estatura,objetivo,w0,meta,dias,exp_meses,consiente,hizo_alta,dias_activo)
where p.id = v.id;

-- ---------- 3. Curva del plan ----------
insert into public.plan_targets (user_id, week, phase, target_weight_kg, target_waist_cm, kcal_target)
select p.id, s, least(4, ceil(s/4.5)::int),
       round((p.initial_weight_kg + (p.target_weight_kg - p.initial_weight_kg) * s / 18.0)::numeric, 1),
       null,
       case p.goal when 'fat_loss' then 1750 when 'muscle_gain' then 2900 else 2150 end
from public.profiles p, generate_series(1,18) s
where p.is_demo and p.onboarded_at is not null
on conflict (user_id, week) do nothing;

-- ---------- 4. Sesiones de entrenamiento ----------
-- Rotación de cuerpo completo A/B/C, 3 ejercicios por sesión, 3 series cada uno.
-- La carga sube 2.5 kg cada dos semanas y se escala por sexo.
with cfg as (
  select * from (values
    -- id, sesiones, días entre sesiones, días desde la última
    ('00000000-0000-4dee-9000-000000000001'::uuid, 22, 2, 1),
    ('00000000-0000-4dee-9000-000000000002'::uuid, 20, 2, 2),
    ('00000000-0000-4dee-9000-000000000003'::uuid, 9,  3, 12),
    ('00000000-0000-4dee-9000-000000000004'::uuid, 14, 2, 3)
  ) as t(uid, n, cada, hace)
)
insert into public.workouts (user_id, client_uid, routine_id, performed_on, session_rpe, duration_min)
select c.uid, 'demo-'||c.uid||'-'||i,
       (select r.id from public.routines r
         where r.slug = (array['fullA','fullB','fullC'])[(i % 3) + 1] and r.owner_id is null),
       current_date - c.hace - (c.n - 1 - i) * c.cada,
       7 + (i % 3), 55 + (i % 4) * 5
from cfg c, generate_series(0, 30) i
where i < c.n
on conflict (user_id, client_uid) do nothing;

-- Series. Beto es el único que NO reporta RIR.
with cfg as (
  select * from (values
    ('00000000-0000-4dee-9000-000000000001'::uuid, true),
    ('00000000-0000-4dee-9000-000000000002'::uuid, false),
    ('00000000-0000-4dee-9000-000000000003'::uuid, true),
    ('00000000-0000-4dee-9000-000000000004'::uuid, true)
  ) as t(uid, con_rir)
)
insert into public.workout_sets (workout_id, exercise_id, set_index, weight_kg, reps, rir)
select w.id, re.exercise_id, g.n,
       greatest(2.5, round((
           (case e.slug
              when 'sentadilla-hack'           then 45
              when 'press-banca-inclinado'     then 30
              when 'remo-unilateral-mancuerna' then 18
              when 'peso-muerto'               then 55
              when 'press-militar-barra'       then 22
              when 'jalon-al-pecho'            then 35
              when 'sentadilla-goblet'         then 20
              when 'fondos-paralelas'          then 10
              when 'dominadas'                 then 5
              else 20 end)
         * (case when p.sex='F' then 0.62 else 1.0 end)
         + 2.5 * floor((w.performed_on - p.plan_start) / 14.0)
       ) / 2.5) * 2.5),
       8 - (g.n - 1),
       case when c.con_rir then greatest(0, 3 - g.n) end
from public.workouts w
join public.profiles p on p.id = w.user_id and p.is_demo
join cfg c on c.uid = w.user_id
join public.routine_exercises re on re.routine_id = w.routine_id and re.order_index <= 3
join public.exercises e on e.id = re.exercise_id
cross join generate_series(1,3) g(n)
on conflict (workout_id, exercise_id, set_index) do nothing;

-- ---------- 5. Peso corporal ----------
insert into public.body_weights (user_id, measured_on, weight_kg)
select p.id, current_date - d,
       round((p.initial_weight_kg
              + (p.target_weight_kg - p.initial_weight_kg) * (56 - d) / 90.0
              + (random() - 0.5) * 0.6)::numeric, 1)
from public.profiles p, generate_series(0, 55) d
where p.is_demo and p.onboarded_at is not null
  and p.id <> '00000000-0000-4dee-9000-000000000004'   -- Dani no se pesa
  and d % 2 = 0                                        -- se pesa día sí día no
on conflict (user_id, measured_on) do nothing;

-- ---------- 6. Alimentación ----------
insert into public.nutrition_logs (user_id, logged_on, kcal, protein_g, carbs_g, fat_g, kcal_target, source)
select p.id, current_date - d,
       (case p.goal when 'fat_loss' then 1750 when 'muscle_gain' then 2900 else 2150 end
        + round((random()-0.5)*260))::int,
       round((p.initial_weight_kg * 1.9 + (random()-0.5)*20)::numeric, 1),
       round((220 + (random()-0.5)*70)::numeric, 1),
       round((65 + (random()-0.5)*20)::numeric, 1),
       case p.goal when 'fat_loss' then 1750 when 'muscle_gain' then 2900 else 2150 end,
       'manual'
from public.profiles p, generate_series(0, 40) d
where p.is_demo
  and p.id in ('00000000-0000-4dee-9000-000000000001',
               '00000000-0000-4dee-9000-000000000003')  -- solo dos llevan la comida
on conflict (user_id, logged_on) do nothing;

-- ---------- 7. Sueño ----------
insert into public.sleep_logs (user_id, logged_on, hours)
select p.id, current_date - d, round((7 + (random()-0.5)*1.8)::numeric, 1)
from public.profiles p, generate_series(0, 30) d
where p.is_demo and p.id = '00000000-0000-4dee-9000-000000000001'
on conflict (user_id, logged_on) do nothing;

-- ---------- Resumen ----------
select codigo, nombre, es_demo, sesiones, series, pct_rir,
       dias_sin_entrenar, dias_peso, dias_comida, consiente, dado_de_alta
from public.v_admin_participantes
order by codigo;
