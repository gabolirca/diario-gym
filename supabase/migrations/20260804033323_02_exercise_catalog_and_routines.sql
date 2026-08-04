-- =====================================================================
-- GymAI · 02 · Catálogo de ejercicios y plantillas de rutina
-- Reemplaza los strings hardcodeados de ROUTINES en index.html.
-- owner_id NULL = catálogo global; owner_id = usuario => ejercicio propio.
-- =====================================================================

create table public.exercises (
  id               bigint generated always as identity primary key,
  owner_id         uuid references public.profiles(id) on delete cascade,
  slug             text not null,
  name             text not null,
  muscle_group     text not null check (muscle_group in
                     ('pecho','espalda','hombro','cuadriceps','isquios','gluteo',
                      'pantorrilla','biceps','triceps','antebrazo','core','cuello')),
  movement_pattern text not null check (movement_pattern in
                     ('empuje_horizontal','empuje_vertical','jale_horizontal','jale_vertical',
                      'sentadilla','bisagra','zancada','aislamiento','core')),
  equipment        text not null check (equipment in
                     ('barra','mancuerna','maquina','polea','peso_corporal','otro')),
  is_compound      boolean not null default false,
  is_unilateral    boolean not null default false,
  -- Incremento mínimo realista en el gimnasio. El modelo redondea a este múltiplo.
  load_increment_kg numeric(4,2) not null default 2.5,
  created_at       timestamptz not null default now()
);

-- slug único dentro del catálogo global y dentro del catálogo de cada usuario
create unique index exercises_slug_global_uk on public.exercises (slug) where owner_id is null;
create unique index exercises_slug_owner_uk  on public.exercises (owner_id, slug) where owner_id is not null;
create index exercises_owner_idx on public.exercises (owner_id);

comment on column public.exercises.load_increment_kg is 'Incremento mínimo utilizable. Define también la tolerancia de error del modelo (MAE objetivo < 1 incremento).';

-- ---------------------------------------------------------------------
create table public.routines (
  id          bigint generated always as identity primary key,
  owner_id    uuid references public.profiles(id) on delete cascade,
  slug        text not null,
  name        text not null,
  focus       text,
  order_index integer not null default 0,
  created_at  timestamptz not null default now()
);

create unique index routines_slug_global_uk on public.routines (slug) where owner_id is null;
create unique index routines_slug_owner_uk  on public.routines (owner_id, slug) where owner_id is not null;

create table public.routine_exercises (
  id               bigint generated always as identity primary key,
  routine_id       bigint not null references public.routines(id) on delete cascade,
  exercise_id      bigint not null references public.exercises(id) on delete restrict,
  order_index      integer not null,
  target_sets      integer not null check (target_sets between 1 and 12),
  target_reps_min  integer check (target_reps_min between 1 and 100),
  target_reps_max  integer check (target_reps_max between 1 and 100),
  -- Ventana de esfuerzo objetivo. Es la definición operativa del target del modelo:
  -- "la carga que deja al usuario dentro de este rango de RIR".
  target_rir_min   numeric(3,1) not null default 1 check (target_rir_min between 0 and 10),
  target_rir_max   numeric(3,1) not null default 3 check (target_rir_max between 0 and 10),
  to_failure       boolean not null default false,
  unique (routine_id, order_index),
  check (target_reps_max is null or target_reps_min is null or target_reps_max >= target_reps_min),
  check (target_rir_max >= target_rir_min)
);

create index routine_exercises_routine_idx on public.routine_exercises (routine_id, order_index);
