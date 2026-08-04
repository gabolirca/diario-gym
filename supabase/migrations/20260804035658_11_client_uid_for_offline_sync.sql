-- =====================================================================
-- GymAI · 11 · Identificador de cliente para sincronización offline
-- workouts y swims no tienen llave natural (puede haber dos sesiones el
-- mismo día). client_uid lo genera el dispositivo y permite hacer upsert
-- idempotente: sincronizar dos veces no duplica registros.
-- =====================================================================

alter table public.workouts add column client_uid text;
alter table public.swims    add column client_uid text;

create unique index workouts_client_uid_uk on public.workouts (user_id, client_uid)
  where client_uid is not null;
create unique index swims_client_uid_uk on public.swims (user_id, client_uid)
  where client_uid is not null;

comment on column public.workouts.client_uid is
  'UUID generado en el dispositivo. Hace idempotente la sincronización offline.';
