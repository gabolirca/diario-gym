-- =====================================================================
-- GymAI · 12 · Corrección: client_uid NOT NULL con restricción única plena
--
-- El índice único PARCIAL (where client_uid is not null) no puede usarse
-- en ON CONFLICT sin repetir el predicado, y supabase-js no permite
-- expresarlo en .upsert({onConflict:'user_id,client_uid'}).
-- Se cambia a NOT NULL con default y restricción única normal.
-- =====================================================================

drop index if exists public.workouts_client_uid_uk;
drop index if exists public.swims_client_uid_uk;

update public.workouts set client_uid = gen_random_uuid()::text where client_uid is null;
update public.swims    set client_uid = gen_random_uuid()::text where client_uid is null;

alter table public.workouts
  alter column client_uid set default gen_random_uuid()::text,
  alter column client_uid set not null,
  add constraint workouts_user_client_uid_uk unique (user_id, client_uid);

alter table public.swims
  alter column client_uid set default gen_random_uuid()::text,
  alter column client_uid set not null,
  add constraint swims_user_client_uid_uk unique (user_id, client_uid);
