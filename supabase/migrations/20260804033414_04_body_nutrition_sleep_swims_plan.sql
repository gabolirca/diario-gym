-- =====================================================================
-- GymAI · 04 · Composición corporal, nutrición, sueño, natación y plan
-- nutrition_logs es tabla NUEVA: hoy la app no registra ingesta, solo
-- muestra una meta calórica estática. Sin esta tabla, la hipótesis H2
-- del anteproyecto (aporte de la nutrición a la predicción) no es
-- verificable.
-- =====================================================================

create table public.body_weights (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  measured_on date not null,
  weight_kg   numeric(5,2) not null check (weight_kg between 20 and 400),
  created_at  timestamptz not null default now(),
  unique (user_id, measured_on)
);
create index body_weights_user_date_idx on public.body_weights (user_id, measured_on desc);

-- ---------------------------------------------------------------------
create table public.body_measures (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  measured_on date not null,
  waist_cm    numeric(5,1) check (waist_cm between 30 and 250),
  neck_cm     numeric(5,1) check (neck_cm between 20 and 100),
  chest_cm    numeric(5,1),
  arm_cm      numeric(5,1),
  thigh_cm    numeric(5,1),
  hip_cm      numeric(5,1),
  created_at  timestamptz not null default now(),
  unique (user_id, measured_on)
);
create index body_measures_user_date_idx on public.body_measures (user_id, measured_on desc);

-- ---------------------------------------------------------------------
create table public.sleep_logs (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  logged_on  date not null,
  hours      numeric(4,2) check (hours between 0 and 24),
  quality    integer check (quality between 1 and 5),
  created_at timestamptz not null default now(),
  unique (user_id, logged_on)
);

-- ---------------------------------------------------------------------
create table public.swims (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  performed_on date not null,
  kind         text not null check (kind in ('intervalos','continuo','tecnica')),
  meters       integer check (meters between 0 and 20000),
  minutes      numeric(6,2) check (minutes between 0 and 600),
  pace_sec_100m integer check (pace_sec_100m between 30 and 600),
  notes        text,
  created_at   timestamptz not null default now()
);
create index swims_user_date_idx on public.swims (user_id, performed_on desc);

-- ---------------------------------------------------------------------
-- NUTRICIÓN — no existe hoy en la app
-- ---------------------------------------------------------------------
create table public.nutrition_logs (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  logged_on    date not null,
  kcal         integer check (kcal between 0 and 12000),
  protein_g    numeric(6,1) check (protein_g between 0 and 600),
  carbs_g      numeric(6,1) check (carbs_g between 0 and 1500),
  fat_g        numeric(6,1) check (fat_g between 0 and 500),
  kcal_target  integer check (kcal_target between 0 and 12000),
  -- 'manual' = el usuario capturó; 'estimated' = derivado del plan.
  -- Distinguirlos importa: solo lo capturado sirve como evidencia.
  source       text not null default 'manual' check (source in ('manual','estimated','imported')),
  notes        text,
  created_at   timestamptz not null default now(),
  unique (user_id, logged_on)
);
create index nutrition_logs_user_date_idx on public.nutrition_logs (user_id, logged_on desc);

comment on table public.nutrition_logs is
  'Registro diario de ingesta. Sustenta las variables nutricionales del modelo (balance energético a 7 días, proteína por kg). Sin datos con source=manual, la hipótesis H2 no es verificable.';

-- ---------------------------------------------------------------------
-- Curva objetivo del plan (equivale al arreglo PLAN del index.html)
-- ---------------------------------------------------------------------
create table public.plan_targets (
  id               bigint generated always as identity primary key,
  user_id          uuid not null references public.profiles(id) on delete cascade,
  week             integer not null check (week between 1 and 104),
  phase            integer check (phase between 1 and 10),
  target_weight_kg numeric(5,2),
  target_waist_cm  numeric(5,1),
  kcal_target      integer,
  milestone        text,
  unique (user_id, week)
);
