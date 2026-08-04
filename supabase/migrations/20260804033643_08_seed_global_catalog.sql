-- =====================================================================
-- GymAI · 08 · Catálogo global, migrado desde ROUTINES de index.html
-- =====================================================================

insert into public.exercises
  (owner_id, slug, name, muscle_group, movement_pattern, equipment, is_compound, is_unilateral, load_increment_kg)
values
  (null,'press-banca-inclinado','Press banca inclinado','pecho','empuje_horizontal','barra',true,false,2.5),
  (null,'press-militar-barra','Press militar con barra','hombro','empuje_vertical','barra',true,false,2.5),
  (null,'fondos-paralelas','Fondos en paralelas','pecho','empuje_vertical','peso_corporal',true,false,2.5),
  (null,'aperturas-mancuerna','Aperturas con mancuerna','pecho','aislamiento','mancuerna',false,false,2.0),
  (null,'extension-triceps-polea','Extensión de tríceps en polea','triceps','aislamiento','polea',false,false,2.5),
  (null,'elevaciones-laterales','Elevaciones laterales','hombro','aislamiento','mancuerna',false,false,2.0),

  (null,'sentadilla-hack','Sentadilla hack','cuadriceps','sentadilla','maquina',true,false,5.0),
  (null,'peso-muerto','Peso muerto','isquios','bisagra','barra',true,false,2.5),
  (null,'prensa','Prensa','cuadriceps','sentadilla','maquina',true,false,5.0),
  (null,'curl-femoral','Curl femoral','isquios','aislamiento','maquina',false,false,5.0),
  (null,'pantorrilla','Pantorrilla','pantorrilla','aislamiento','maquina',false,false,5.0),

  (null,'dominadas','Dominadas','espalda','jale_vertical','peso_corporal',true,false,2.5),
  (null,'jalon-al-pecho','Jalón al pecho','espalda','jale_vertical','polea',true,false,2.5),
  (null,'remo-unilateral-mancuerna','Remo unilateral mancuerna','espalda','jale_horizontal','mancuerna',true,true,2.0),
  (null,'remo-alto-abierto','Remo alto abierto','hombro','jale_horizontal','polea',true,false,2.5),
  (null,'curl-biceps-barra','Curl de bíceps con barra','biceps','aislamiento','barra',false,false,2.5),
  (null,'antebrazo','Antebrazo','antebrazo','aislamiento','barra',false,false,2.5),

  (null,'sentadilla-goblet','Sentadilla goblet','cuadriceps','sentadilla','mancuerna',true,false,2.0),
  (null,'extension-cuadriceps','Extensión de cuádriceps','cuadriceps','aislamiento','maquina',false,false,5.0),
  (null,'desplantes','Desplantes','cuadriceps','zancada','mancuerna',true,true,2.0),
  (null,'bulgaras','Búlgaras','gluteo','zancada','mancuerna',true,true,2.0),
  (null,'hiperextension-baja','Hiperextensión baja','gluteo','bisagra','peso_corporal',true,false,2.5),
  (null,'abductor','Abductor','gluteo','aislamiento','maquina',false,false,5.0),

  (null,'press-militar-mancuernas','Press militar mancuernas','hombro','empuje_vertical','mancuerna',true,false,2.0),
  (null,'elevaciones-frontales','Elevaciones frontales','hombro','aislamiento','mancuerna',false,false,2.0),
  (null,'posterior-pajaros','Posterior (pájaros)','hombro','aislamiento','mancuerna',false,false,2.0),
  (null,'curl-spider','Curl spider','biceps','aislamiento','mancuerna',false,false,2.0),
  (null,'press-frances','Press francés','triceps','aislamiento','barra',false,false,2.5),
  (null,'trabajo-cuello','Trabajo de cuello','cuello','aislamiento','otro',false,false,2.5);

-- ---------------------------------------------------------------------
insert into public.routines (owner_id, slug, name, focus, order_index) values
  (null,'upperA','Upper A — Empuje','empuje',1),
  (null,'lowerA','Lower A — Fuerza','fuerza',2),
  (null,'upperB','Upper B — Jale','jale',3),
  (null,'lowerB','Lower B — Volumen','volumen',4),
  (null,'upperC','Upper C — Hombro y brazo','hombro_brazo',5);

-- ---------------------------------------------------------------------
insert into public.routine_exercises
  (routine_id, exercise_id, order_index, target_sets, target_reps_min, target_reps_max,
   target_rir_min, target_rir_max, to_failure)
select r.id, e.id, v.ord, v.sets, v.rmin, v.rmax, v.rir_min, v.rir_max, v.fail
from (values
  -- Upper A
  ('upperA','press-banca-inclinado',      1,4, 6, 8,1,3,false),
  ('upperA','press-militar-barra',        2,4, 8,10,1,3,false),
  ('upperA','fondos-paralelas',           3,3, 8,10,1,3,false),
  ('upperA','aperturas-mancuerna',        4,3,10,12,1,2,false),
  ('upperA','extension-triceps-polea',    5,3,10,12,1,2,false),
  ('upperA','elevaciones-laterales',      6,3,12,15,0,2,false),
  -- Lower A
  ('lowerA','sentadilla-hack',            1,4, 6, 8,1,3,false),
  ('lowerA','peso-muerto',                2,4, 4, 6,2,3,false),
  ('lowerA','prensa',                     3,3, 8,10,1,3,false),
  ('lowerA','curl-femoral',               4,3,10,12,1,2,false),
  ('lowerA','pantorrilla',                5,4,12,15,0,2,false),
  -- Upper B
  ('upperB','dominadas',                  1,4, 4,12,0,1,true ),
  ('upperB','jalon-al-pecho',             2,3,10,12,1,2,false),
  ('upperB','remo-unilateral-mancuerna',  3,4, 8,10,1,3,false),
  ('upperB','remo-alto-abierto',          4,3,10,12,1,2,false),
  ('upperB','curl-biceps-barra',          5,3, 8,10,1,2,false),
  ('upperB','antebrazo',                  6,3,12,15,0,2,false),
  -- Lower B
  ('lowerB','sentadilla-goblet',          1,3,10,12,1,3,false),
  ('lowerB','extension-cuadriceps',       2,4,10,12,1,2,false),
  ('lowerB','desplantes',                 3,3,12,15,1,2,false),
  ('lowerB','bulgaras',                   4,3,10,12,1,2,false),
  ('lowerB','hiperextension-baja',        5,3,12,15,1,3,false),
  ('lowerB','abductor',                   6,3,12,15,0,2,false),
  -- Upper C
  ('upperC','press-militar-mancuernas',   1,3,10,12,1,3,false),
  ('upperC','elevaciones-frontales',      2,3,10,12,1,2,false),
  ('upperC','posterior-pajaros',          3,4,12,15,0,2,false),
  ('upperC','curl-spider',                4,3,10,12,1,2,false),
  ('upperC','press-frances',              5,3,10,12,1,2,false),
  ('upperC','trabajo-cuello',             6,2,12,15,2,3,false)
) as v(rslug, eslug, ord, sets, rmin, rmax, rir_min, rir_max, fail)
join public.routines  r on r.slug = v.rslug and r.owner_id is null
join public.exercises e on e.slug = v.eslug and e.owner_id is null;
