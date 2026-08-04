-- =====================================================================
-- Contenido para la migración que crearás DESPUÉS de `supabase db pull`
--
--   npx supabase migration new auth_trigger_y_endurecimiento
--
-- y pegas esto en el archivo que te genere.
--
-- ¿Por qué aparte? `db pull` solo vuelca el esquema `public`. El trigger
-- que crea el perfil al registrarse vive en `auth.users`, así que NO lo
-- captura. Sin este archivo, un `supabase db reset` dejaría la base sin
-- alta automática de perfiles y el registro de usuarios fallaría en
-- silencio.
--
-- Todo aquí es idempotente: correrlo dos veces no rompe nada.
-- =====================================================================

-- Crea el perfil automáticamente cuando alguien se registra
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Endurecimiento: search_path fijo y sin EXECUTE público.
-- Son funciones de trigger; nadie debe poder llamarlas por la API REST.
alter function public.touch_updated_at()      set search_path = public, pg_temp;
alter function public.stamp_consent()         set search_path = public, pg_temp;
alter function public.handle_new_user()       set search_path = public, pg_temp;
alter function public.close_prediction_loop() set search_path = public, pg_temp;

revoke all on function public.touch_updated_at()      from public, anon, authenticated;
revoke all on function public.stamp_consent()         from public, anon, authenticated;
revoke all on function public.handle_new_user()       from public, anon, authenticated;
revoke all on function public.close_prediction_loop() from public, anon, authenticated;
