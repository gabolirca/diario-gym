-- =====================================================================
-- GymAI · 16 · es_admin() fuera del esquema expuesto
--
-- En `public`, PostgREST la publica como /rest/v1/rpc/es_admin. No filtra
-- nada (solo dice si QUIEN LLAMA es investigador), pero una función
-- SECURITY DEFINER no tiene por qué estar en la superficie de la API.
-- Se mueve a un esquema privado: las políticas la siguen usando, la API
-- no la ve.
-- =====================================================================

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;   -- necesario para evaluar las políticas

create or replace function private.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false);
$$;

revoke all on function private.es_admin() from public, anon;
grant execute on function private.es_admin() to authenticated;

-- ---------------------------------------------------------------------
-- Recrear las políticas de lectura apuntando al esquema privado
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['workouts','body_weights','body_measures','sleep_logs',
                           'swims','nutrition_logs','plan_targets','predictions']
  loop
    execute format('drop policy if exists %1$s_select on public.%1$s', t);
    execute format(
      'create policy %1$s_select on public.%1$s for select to authenticated
         using ((select auth.uid()) = user_id or private.es_admin())', t);
  end loop;
end $$;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id or private.es_admin());

drop policy if exists workout_sets_select on public.workout_sets;
create policy workout_sets_select on public.workout_sets
  for select to authenticated
  using (exists (select 1 from public.workouts w
                  where w.id = workout_id
                    and (w.user_id = (select auth.uid()) or private.es_admin())));

drop function if exists public.es_admin();
