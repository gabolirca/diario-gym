-- =====================================================================
-- GymAI · 03 · Sesiones y series
-- workout_sets es el núcleo del proyecto: aquí vive el RIR, que es
-- la variable que define el objetivo del modelo predictivo.
-- =====================================================================

create table public.workouts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  routine_id   bigint references public.routines(id) on delete set null,
  performed_on date not null,
  started_at   timestamptz,
  duration_min integer check (duration_min between 1 and 600),
  -- Esfuerzo global de la sesión (escala 0-10). Distinto del RIR por serie.
  session_rpe  numeric(3,1) check (session_rpe between 0 and 10),
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index workouts_user_date_idx on public.workouts (user_id, performed_on desc);

create trigger workouts_touch
  before update on public.workouts
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
create table public.workout_sets (
  id           bigint generated always as identity primary key,
  workout_id   bigint not null references public.workouts(id) on delete cascade,
  exercise_id  bigint not null references public.exercises(id) on delete restrict,
  set_index    integer not null check (set_index between 1 and 50),
  weight_kg    numeric(6,2) not null check (weight_kg >= 0),
  reps         integer not null check (reps between 0 and 200),

  -- ================= EL CAMPO CRÍTICO =================
  -- Repeticiones en reserva. Sin esto no hay aprendizaje supervisado:
  -- es lo que permite saber si la carga fue adecuada, corta o excesiva.
  -- Nullable a propósito: es mejor un dato faltante que un dato inventado.
  rir          numeric(3,1) check (rir between 0 and 10),
  -- ====================================================

  to_failure   boolean not null default false,
  is_warmup    boolean not null default false,
  tempo        text,
  rest_sec     integer check (rest_sec between 0 and 1800),
  notes        text,
  created_at   timestamptz not null default now(),

  -- Métricas derivadas, calculadas por Postgres para no duplicar lógica en el cliente
  volume_kg    numeric(10,2) generated always as (weight_kg * reps) stored,
  -- 1RM estimado por la fórmula de Epley, la misma que ya usa la app
  e1rm_kg      numeric(8,2) generated always as
                 (case when reps > 0 then weight_kg * (1 + reps / 30.0) else null end) stored,

  unique (workout_id, exercise_id, set_index)
);

create index workout_sets_workout_idx  on public.workout_sets (workout_id);
create index workout_sets_exercise_idx on public.workout_sets (exercise_id);
-- Índice que sostiene las consultas de historial por usuario y ejercicio
create index workout_sets_hist_idx on public.workout_sets (exercise_id, workout_id desc)
  where not is_warmup;

comment on column public.workout_sets.rir is
  'Repeticiones en reserva reportadas por el usuario. Variable central del modelo: define si la carga cayó en la ventana objetivo. NULL = no reportado, se excluye del entrenamiento supervisado.';
comment on column public.workout_sets.e1rm_kg is 'Máximo estimado en una repetición (Epley). Calculado, no capturado.';
