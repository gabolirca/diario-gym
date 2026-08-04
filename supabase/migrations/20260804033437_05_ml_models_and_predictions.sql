-- =====================================================================
-- GymAI · 05 · Trazabilidad del modelo
-- Estas dos tablas son lo que convierte el desarrollo en investigación:
-- permiten medir el error del modelo EN PRODUCCIÓN contra lo que el
-- usuario realmente levantó, no solo en el conjunto de prueba.
-- =====================================================================

create table public.model_versions (
  id          bigint generated always as identity primary key,
  version     text not null unique,          -- p.ej. 'progresion-v0.3.1'
  model_kind  text not null check (model_kind in ('arranque_frio','progresion','descarga')),
  algorithm   text not null,                 -- 'baseline_lineal' | 'ridge' | 'random_forest' | 'gradient_boosting'
  trained_at  timestamptz not null default now(),
  n_samples   integer,
  n_users     integer,
  -- Métricas del anteproyecto: mae_kg, rmse_kg, acc_within_increment, mejora_vs_baseline
  metrics     jsonb not null default '{}'::jsonb,
  feature_set jsonb not null default '[]'::jsonb,
  notes       text,
  is_active   boolean not null default false
);

-- Solo un modelo activo por tipo
create unique index model_versions_one_active_uk
  on public.model_versions (model_kind) where is_active;

-- ---------------------------------------------------------------------
create table public.predictions (
  id                 bigint generated always as identity primary key,
  user_id            uuid   not null references public.profiles(id) on delete cascade,
  exercise_id        bigint not null references public.exercises(id) on delete cascade,
  model_version_id   bigint references public.model_versions(id) on delete set null,
  predicted_for      date not null,           -- fecha de la sesión que se está prescribiendo
  predicted_weight_kg numeric(6,2) not null,
  predicted_reps     integer,
  target_rir         numeric(3,1),
  -- Snapshot de las variables usadas. Indispensable para reproducir y auditar.
  features           jsonb not null default '{}'::jsonb,
  -- Salida cruda del modelo antes de la capa de restricciones de seguridad
  raw_weight_kg      numeric(6,2),
  clamped            boolean not null default false,
  clamp_reason       text,
  -- Se llena a posteriori con lo que el usuario realmente hizo
  actual_set_id      bigint references public.workout_sets(id) on delete set null,
  error_kg           numeric(6,2),
  created_at         timestamptz not null default now()
);

create index predictions_user_idx on public.predictions (user_id, predicted_for desc);
create index predictions_open_idx on public.predictions (user_id, exercise_id, predicted_for)
  where actual_set_id is null;

comment on column public.predictions.clamped is
  'true si la capa de restricciones de seguridad modificó la salida del modelo. Permite cuantificar cuántas veces el modelo propuso algo inseguro.';
comment on column public.predictions.error_kg is
  'predicted_weight_kg - carga real ejecutada. Base del MAE en producción.';

-- Cierra el ciclo: al registrar una serie, liga la predicción abierta y calcula el error
create or replace function public.close_prediction_loop()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid;
  v_date date;
begin
  if new.is_warmup then return new; end if;

  select w.user_id, w.performed_on into v_user, v_date
  from public.workouts w where w.id = new.workout_id;

  update public.predictions p
     set actual_set_id = new.id,
         error_kg      = p.predicted_weight_kg - new.weight_kg
   where p.id = (
     select p2.id from public.predictions p2
      where p2.user_id       = v_user
        and p2.exercise_id   = new.exercise_id
        and p2.predicted_for = v_date
        and p2.actual_set_id is null
      order by p2.created_at
      limit 1
   );

  return new;
end;
$$;

create trigger workout_sets_close_prediction
  after insert on public.workout_sets
  for each row execute function public.close_prediction_loop();
