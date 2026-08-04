-- =====================================================================
-- GymAI · 13 · Campos de alta y rutinas de cuerpo completo
-- Necesarios para que un participante nuevo pueda darse de alta solo,
-- sin heredar el plan del autor.
-- =====================================================================

alter table public.profiles
  add column training_days_per_week integer check (training_days_per_week between 2 and 7),
  add column target_weight_kg numeric(5,2) check (target_weight_kg between 30 and 300),
  add column target_waist_cm  numeric(5,1) check (target_waist_cm between 40 and 200),
  add column onboarded_at     timestamptz;

comment on column public.profiles.training_days_per_week is
  'Días por semana que el participante puede entrenar. Determina qué programa se le asigna: 3 = cuerpo completo, 4 = torso/pierna, 5 = split.';
comment on column public.profiles.onboarded_at is
  'Marca que el cuestionario inicial se completó. Si es NULL, la app muestra el alta.';

-- ---------------------------------------------------------------------
-- Rutinas de cuerpo completo, para quien solo puede entrenar 3 días.
-- Usan ejercicios que ya existen en el catálogo global.
-- ---------------------------------------------------------------------
insert into public.routines (owner_id, slug, name, focus, order_index) values
  (null,'fullA','Cuerpo completo A','cuerpo_completo',6),
  (null,'fullB','Cuerpo completo B','cuerpo_completo',7),
  (null,'fullC','Cuerpo completo C','cuerpo_completo',8);

insert into public.routine_exercises
  (routine_id, exercise_id, order_index, target_sets, target_reps_min, target_reps_max,
   target_rir_min, target_rir_max, to_failure)
select r.id, e.id, v.ord, v.sets, v.rmin, v.rmax, v.rir_min, v.rir_max, false
from (values
  -- A · sentadilla + empuje horizontal + jale horizontal
  ('fullA','sentadilla-hack',            1,3, 6, 8,1,3),
  ('fullA','press-banca-inclinado',      2,3, 6, 8,1,3),
  ('fullA','remo-unilateral-mancuerna',  3,3, 8,10,1,3),
  ('fullA','curl-femoral',               4,3,10,12,1,2),
  ('fullA','elevaciones-laterales',      5,3,12,15,0,2),
  -- B · bisagra + empuje vertical + jale vertical
  ('fullB','peso-muerto',                1,3, 4, 6,2,3),
  ('fullB','press-militar-barra',        2,3, 8,10,1,3),
  ('fullB','jalon-al-pecho',             3,3,10,12,1,2),
  ('fullB','prensa',                     4,3,10,12,1,3),
  ('fullB','curl-biceps-barra',          5,3, 8,10,1,2),
  -- C · unilateral + peso corporal
  ('fullC','sentadilla-goblet',          1,3,10,12,1,3),
  ('fullC','fondos-paralelas',           2,3, 8,10,1,3),
  ('fullC','dominadas',                  3,3, 4,12,0,1),
  ('fullC','hiperextension-baja',        4,3,12,15,1,3),
  ('fullC','extension-triceps-polea',    5,3,10,12,1,2)
) as v(rslug, eslug, ord, sets, rmin, rmax, rir_min, rir_max)
join public.routines  r on r.slug = v.rslug and r.owner_id is null
join public.exercises e on e.slug = v.eslug and e.owner_id is null;
