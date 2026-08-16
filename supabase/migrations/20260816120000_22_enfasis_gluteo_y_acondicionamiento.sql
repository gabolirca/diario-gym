-- =====================================================================
-- GymAI · 22 · Énfasis del entrenamiento · Glúteo · Acondicionamiento
--
-- Tres cambios que salen de la misma observación: el programa era el
-- mismo para todo el mundo.
--
-- 1. ÉNFASIS. Una persona puede querer priorizar tren superior o
--    inferior. La tentación era deducirlo del sexo —«a las mujeres,
--    pierna»— y eso está mal por dos razones. La primera es que no hay
--    evidencia de que el sexo exija un programa distinto para la
--    hipertrofia: la diferencia real es de preferencia. La segunda es de
--    diseño del estudio: si el sexo cambia el tratamiento sin
--    justificación fisiológica, queda como variable de confusión.
--    Se pregunta. El sexo solo decide qué opción llega preseleccionada.
--
-- 2. GLÚTEO. Una rutina más de tren inferior, para quien elige ese
--    énfasis. No es «la rutina de mujeres»: es la rutina de quien pidió
--    más pierna.
--
-- 3. ACONDICIONAMIENTO. Un circuito corporal de sábado. Se registra como
--    cualquier sesión para que quede constancia, pero NO puede entrar al
--    conjunto del modelo: no tiene carga progresiva ni ventana de RIR, y
--    mezclarlo ensuciaría las series de fuerza. El filtro va en
--    v_working_sets, que es de donde cuelgan los récords, el volumen y
--    v_ml_dataset: filtrando ahí, se filtra en todas.
-- =====================================================================

alter table public.profiles add column if not exists training_emphasis text
  check (training_emphasis in ('equilibrado','superior','inferior'));

comment on column public.profiles.training_emphasis is
  'Qué mitad del cuerpo quiere priorizar la persona. Se PREGUNTA en el cuestionario; el sexo solo decide el valor preseleccionado. No hay evidencia de que el sexo exija un programa distinto: la diferencia real es de preferencia, y registrarla como elección permite analizarla sin confundirla con fisiología.';

alter table public.routines add column if not exists kind text not null default 'fuerza'
  check (kind in ('fuerza','acondicionamiento'));

comment on column public.routines.kind is
  'acondicionamiento = circuito por tiempo. No entra al conjunto del modelo: no tiene carga progresiva ni ventana de RIR, y mezclarlo ensuciaría las series de fuerza.';

-- Los índices únicos de slug son PARCIALES (where owner_id is null): el
-- on conflict tiene que repetir esa condición o Postgres no lo reconoce.
-- Y load_increment_kg es NOT NULL: en los de peso corporal se pone 1 kg, que
-- es el escalón de un chaleco o de una mancuerna chica.
insert into public.exercises (slug, name, muscle_group, movement_pattern, equipment,
                              is_compound, is_unilateral, load_increment_kg, owner_id)
values
  ('empuje-cadera','Empuje de cadera','gluteo','bisagra','barra',true,false,5.0,null),
  ('peso-muerto-rumano','Peso muerto rumano','isquios','bisagra','barra',true,false,2.5,null),
  ('patada-gluteo-polea','Patada de glúteo en polea','gluteo','aislamiento','polea',false,true,2.5,null),
  ('burpees','Burpees','core','core','peso_corporal',true,false,1.0,null),
  ('sentadilla-con-salto','Sentadilla con salto','cuadriceps','sentadilla','peso_corporal',true,false,1.0,null),
  ('escaladores','Escaladores','core','core','peso_corporal',true,false,1.0,null),
  ('swing-ruso','Swing ruso','gluteo','bisagra','otro',true,false,4.0,null)
on conflict (slug) where owner_id is null do nothing;

insert into public.routines (slug, name, focus, order_index, kind, owner_id)
values ('lowerC','Lower C — Glúteo y cadena posterior','gluteo',9,'fuerza',null),
       ('acond','Sábado — Acondicionamiento','acondicionamiento',10,'acondicionamiento',null)
on conflict (slug) where owner_id is null do nothing;

insert into public.routine_exercises (routine_id, exercise_id, order_index, target_sets,
                                      target_reps_min, target_reps_max, target_rir_min, target_rir_max)
select r.id, e.id, v.ord, v.sets, v.rmin, v.rmax, v.rirmin, v.rirmax
from (values
  ('lowerC','empuje-cadera',1,4,8,10,1,3),
  ('lowerC','peso-muerto-rumano',2,4,8,10,1,3),
  ('lowerC','bulgaras',3,3,10,12,1,3),
  ('lowerC','patada-gluteo-polea',4,3,12,15,0,2),
  ('lowerC','abductor',5,3,12,15,0,2),
  ('lowerC','pantorrilla',6,4,12,15,0,2),
  ('acond','burpees',1,4,10,15,0,2),
  ('acond','swing-ruso',2,4,15,20,1,3),
  ('acond','sentadilla-con-salto',3,4,12,15,0,2),
  ('acond','escaladores',4,4,20,30,0,2),
  ('acond','desplantes',5,3,12,15,0,2)
) as v(rut,slug,ord,sets,rmin,rmax,rirmin,rirmax)
join public.routines  r on r.slug = v.rut  and r.owner_id is null
join public.exercises e on e.slug = v.slug and e.owner_id is null
on conflict (routine_id, order_index) do nothing;

create or replace view public.v_working_sets as
select
  ws.id as set_id, w.user_id, w.id as workout_id, w.performed_on,
  ws.exercise_id, ws.set_index, ws.weight_kg, ws.reps, ws.rir,
  ws.to_failure, ws.volume_kg, ws.e1rm_kg
from public.workout_sets ws
join public.workouts w on w.id = ws.workout_id
left join public.routines r on r.id = w.routine_id
where not ws.is_warmup
  and coalesce(r.kind, 'fuerza') <> 'acondicionamiento';

alter view public.v_working_sets set (security_invoker = on);

comment on view public.v_working_sets is
  'Series efectivas de trabajo de fuerza. Excluye calentamiento y sesiones de acondicionamiento: un circuito por tiempo no tiene carga progresiva y contaminaría las series del modelo.';
