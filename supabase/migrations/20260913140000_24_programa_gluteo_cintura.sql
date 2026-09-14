-- =====================================================================
-- GymAI · 24 · Programa «Glúteo y cintura» (6 días)
--
-- Seis días de tren inferior con abdomen y cardio, tomados de una rutina
-- real escrita por una entrenadora. Sustituye al programa genérico de
-- 6 días cuando la persona elige énfasis inferior.
--
-- El énfasis se sigue PREGUNTANDO. A una mujer se le preselecciona
-- «inferior», así que este programa es el que recibe por omisión, pero un
-- hombre que quiera pierna también puede pedirlo y una mujer puede
-- elegir otro. El código no ramifica por sexo en ningún punto.
--
-- CARDIO. Se registra como un ejercicio más, con los minutos en el campo
-- de repeticiones, porque así la persona ve que le toca y queda
-- constancia de que lo hizo. Pero 20 minutos de caminadora no tienen
-- carga ni RIR: si entraran al tonelaje inflarían el volumen semanal y
-- ensuciarían el conjunto del modelo con filas que no son fuerza. Por eso
-- exercises.kind los marca y v_working_sets los deja fuera, igual que ya
-- hacía con las sesiones de acondicionamiento.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. El cardio no es trabajo de fuerza
-- ---------------------------------------------------------------------
alter table public.exercises drop constraint if exists exercises_muscle_group_check;
alter table public.exercises add constraint exercises_muscle_group_check
  check (muscle_group in ('pecho','espalda','hombro','cuadriceps','isquios','gluteo',
                          'pantorrilla','biceps','triceps','antebrazo','core','cuello','cardio'));

alter table public.exercises drop constraint if exists exercises_movement_pattern_check;
alter table public.exercises add constraint exercises_movement_pattern_check
  check (movement_pattern in ('empuje_horizontal','empuje_vertical','jale_horizontal','jale_vertical',
                              'sentadilla','bisagra','zancada','aislamiento','core','cardio'));

alter table public.exercises add column if not exists kind text not null default 'fuerza'
  check (kind in ('fuerza','cardio'));

comment on column public.exercises.kind is
  'cardio = trabajo aeróbico registrado en minutos. Se captura como cualquier ejercicio para que quede constancia, pero queda fuera de v_working_sets: 20 minutos de caminadora no tienen carga ni RIR y meterlos al tonelaje inflaría el volumen y ensuciaría el conjunto del modelo.';

-- ---------------------------------------------------------------------
-- 2. Ejercicios nuevos
-- ---------------------------------------------------------------------
insert into public.exercises (slug, name, muscle_group, movement_pattern, equipment,
                              is_compound, is_unilateral, load_increment_kg, kind, owner_id)
values
  ('aductor','Aductor','cuadriceps','aislamiento','maquina',false,false,5.0,'fuerza',null),
  ('crunch-abdominal','Crunch abdominal','core','core','peso_corporal',false,false,1.0,'fuerza',null),
  ('crunch-polea','Crunch abdominal en polea','core','core','polea',false,false,2.5,'fuerza',null),
  ('plancha','Plancha','core','core','peso_corporal',false,false,1.0,'fuerza',null),
  ('russian-twist','Russian twist','core','core','peso_corporal',false,false,1.0,'fuerza',null),
  ('elevacion-piernas','Elevación de piernas','core','core','peso_corporal',false,false,1.0,'fuerza',null),
  ('step-up','Step up','gluteo','zancada','mancuerna',true,true,2.0,'fuerza',null),
  ('sentadilla-sumo','Sentadilla sumo','gluteo','sentadilla','mancuerna',true,false,2.5,'fuerza',null),
  ('curl-predicador','Curl predicador','biceps','aislamiento','maquina',false,false,2.5,'fuerza',null),
  ('cardio','Cardio','cardio','cardio','otro',false,false,1.0,'cardio',null)
on conflict (slug) where owner_id is null do nothing;

-- ---------------------------------------------------------------------
-- 3. Los seis días
-- ---------------------------------------------------------------------
insert into public.routines (slug, name, focus, order_index, kind, owner_id)
values
  ('gcLun','Lunes — Pierna completa y abdomen','gluteo',11,'fuerza',null),
  ('gcMar','Martes — Jale y abdomen','jale',12,'fuerza',null),
  ('gcMie','Miércoles — Glúteo','gluteo',13,'fuerza',null),
  ('gcJue','Jueves — Brazo completo','hombro_brazo',14,'fuerza',null),
  ('gcVie','Viernes — Femoral y glúteo','gluteo',15,'fuerza',null),
  ('gcSab','Sábado — Empuje','empuje',16,'fuerza',null)
on conflict (slug) where owner_id is null do nothing;

insert into public.routine_exercises (routine_id, exercise_id, order_index, target_sets,
                                      target_reps_min, target_reps_max, target_rir_min, target_rir_max)
select r.id, e.id, v.ord, v.sets, v.rmin, v.rmax, v.rirmin, v.rirmax
from (values
  ('gcLun','extension-cuadriceps',1,4,8,10,1,3),
  ('gcLun','sentadilla-hack',2,3,10,12,0,2),
  ('gcLun','peso-muerto',3,2,8,10,0,2),
  ('gcLun','prensa',4,4,10,12,1,3),
  ('gcLun','aductor',5,3,15,25,0,1),
  ('gcLun','crunch-abdominal',6,4,12,15,0,2),
  ('gcLun','cardio',7,1,20,20,3,3),

  ('gcMar','jalon-al-pecho',1,4,8,10,1,3),
  ('gcMar','remo-unilateral-mancuerna',2,3,10,12,0,2),
  ('gcMar','remo-alto-abierto',3,4,10,12,1,3),
  ('gcMar','hiperextension-baja',4,2,18,20,2,3),
  ('gcMar','curl-biceps-barra',5,3,8,10,1,3),
  ('gcMar','plancha',6,2,60,60,0,2),
  ('gcMar','cardio',7,1,20,20,3,3),

  ('gcMie','empuje-cadera',1,4,8,10,0,2),
  ('gcMie','bulgaras',2,2,12,15,1,3),
  ('gcMie','patada-gluteo-polea',3,3,8,10,0,2),
  ('gcMie','step-up',4,3,12,15,2,3),
  ('gcMie','pantorrilla',5,4,12,15,0,2),
  ('gcMie','russian-twist',6,2,20,40,0,1),
  ('gcMie','cardio',7,1,20,20,3,3),

  ('gcJue','press-militar-barra',1,2,8,10,0,2),
  ('gcJue','elevaciones-laterales',2,3,12,15,1,3),
  ('gcJue','elevaciones-frontales',3,4,8,10,0,2),
  ('gcJue','extension-triceps-polea',4,4,10,12,0,2),
  ('gcJue','curl-predicador',5,2,10,20,0,1),
  ('gcJue','crunch-polea',6,3,8,10,0,2),
  ('gcJue','cardio',7,1,15,15,2,3),

  ('gcVie','peso-muerto',1,4,8,10,0,2),
  ('gcVie','sentadilla-sumo',2,3,12,15,0,2),
  ('gcVie','abductor',3,2,18,20,1,3),
  ('gcVie','bulgaras',4,3,10,12,2,3),
  ('gcVie','desplantes',5,4,10,12,0,2),
  ('gcVie','elevacion-piernas',6,4,5,8,0,2),
  ('gcVie','cardio',7,1,20,20,3,3),

  ('gcSab','press-banca-inclinado',1,4,8,10,0,2),
  ('gcSab','press-militar-barra',2,2,8,10,0,2),
  ('gcSab','aperturas-mancuerna',3,3,10,12,1,3),
  ('gcSab','press-frances',4,4,12,15,1,3),
  ('gcSab','elevaciones-laterales',5,3,8,10,0,2),
  ('gcSab','cardio',6,1,20,20,3,3)
) as v(rut,slug,ord,sets,rmin,rmax,rirmin,rirmax)
join public.routines  r on r.slug = v.rut  and r.owner_id is null
join public.exercises e on e.slug = v.slug and e.owner_id is null
on conflict (routine_id, order_index) do nothing;

-- ---------------------------------------------------------------------
-- 4. El cardio queda fuera del análisis de fuerza
-- ---------------------------------------------------------------------
create or replace view public.v_working_sets as
select
  ws.id as set_id, w.user_id, w.id as workout_id, w.performed_on,
  ws.exercise_id, ws.set_index, ws.weight_kg, ws.reps, ws.rir,
  ws.to_failure, ws.volume_kg, ws.e1rm_kg
from public.workout_sets ws
join public.workouts w on w.id = ws.workout_id
join public.exercises e on e.id = ws.exercise_id
left join public.routines r on r.id = w.routine_id
where not ws.is_warmup
  and coalesce(r.kind, 'fuerza') <> 'acondicionamiento'
  and coalesce(e.kind, 'fuerza') <> 'cardio';

alter view public.v_working_sets set (security_invoker = on);

comment on view public.v_working_sets is
  'Series efectivas de trabajo de fuerza. Excluye calentamiento, sesiones de acondicionamiento y ejercicios de cardio: ninguno tiene carga progresiva y todos ensuciarían el tonelaje, los récords y el conjunto del modelo.';
