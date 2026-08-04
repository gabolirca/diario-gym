-- =====================================================================
-- GymAI · 01 · Perfiles de usuario y utilidades comunes
-- =====================================================================

create extension if not exists "pgcrypto";

-- Actualiza updated_at en cada UPDATE
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- profiles: extiende auth.users con los datos que el modelo necesita
-- ---------------------------------------------------------------------
create table public.profiles (
  id                 uuid primary key references auth.users(id) on delete cascade,
  display_name       text,
  sex                text check (sex in ('M','F')),
  birth_date         date,
  height_cm          numeric(5,1) check (height_cm between 100 and 250),
  training_since     date,                       -- para derivar meses de experiencia
  goal               text check (goal in ('recomp','fat_loss','muscle_gain','strength','maintenance')),
  plan_start         date,
  plan_weeks         integer default 26 check (plan_weeks > 0),
  initial_weight_kg  numeric(5,2),
  -- Consentimiento explícito para uso de los datos en la investigación.
  -- Sin esto marcado, el registro no debe entrar al dataset de entrenamiento.
  research_consent   boolean not null default false,
  consent_granted_at timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table  public.profiles is 'Perfil del usuario. Fuente de las variables antropométricas del modelo.';
comment on column public.profiles.research_consent is 'Si es false, los datos del usuario quedan excluidos del dataset de entrenamiento.';

create trigger profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Sella la fecha de consentimiento la primera vez que se activa
create or replace function public.stamp_consent()
returns trigger
language plpgsql
as $$
begin
  if new.research_consent and (old.research_consent is distinct from true) then
    new.consent_granted_at := now();
  elsif not new.research_consent then
    new.consent_granted_at := null;
  end if;
  return new;
end;
$$;

create trigger profiles_stamp_consent
  before update on public.profiles
  for each row execute function public.stamp_consent();

-- Crea el perfil automáticamente al registrarse
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
