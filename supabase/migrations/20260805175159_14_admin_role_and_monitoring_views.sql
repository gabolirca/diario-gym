-- =====================================================================
-- GymAI · 14 · Rol de investigador y vistas de seguimiento
--
-- El panel NO puede usar la llave service_role: el sitio es estático y
-- público, y esa llave salta toda la seguridad. En su lugar se marca al
-- investigador en su propio perfil y se le permite LEER (nunca escribir)
-- los datos del estudio.
-- =====================================================================

alter table public.profiles add column is_admin boolean not null default false;

comment on column public.profiles.is_admin is
  'Investigador responsable. Solo concede lectura de los datos del estudio, nunca escritura.';

-- Función SECURITY DEFINER: consultar profiles desde una política sobre
-- profiles causaría recursión infinita. Al saltarse RLS aquí, se evita.
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false);
$$;

revoke all on function public.es_admin() from public, anon;
grant execute on function public.es_admin() to authenticated;

-- ---------------------------------------------------------------------
-- Se separan las políticas: lectura para el dueño O el investigador;
-- escritura solo para el dueño. Una sola política de SELECT por tabla
-- evita duplicar la evaluación en cada consulta.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['workouts','body_weights','body_measures','sleep_logs',
                           'swims','nutrition_logs','plan_targets','predictions']
  loop
    execute format('drop policy if exists %1$s_own on public.%1$s', t);
    execute format(
      'create policy %1$s_select on public.%1$s for select to authenticated
         using ((select auth.uid()) = user_id or public.es_admin())', t);
    execute format(
      'create policy %1$s_insert on public.%1$s for insert to authenticated
         with check ((select auth.uid()) = user_id)', t);
    execute format(
      'create policy %1$s_update on public.%1$s for update to authenticated
         using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', t);
    execute format(
      'create policy %1$s_delete on public.%1$s for delete to authenticated
         using ((select auth.uid()) = user_id)', t);
  end loop;
end $$;

-- profiles
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using ((select auth.uid()) = id or public.es_admin());

-- workout_sets hereda del workout padre
drop policy if exists workout_sets_own on public.workout_sets;
create policy workout_sets_select on public.workout_sets
  for select to authenticated
  using (exists (select 1 from public.workouts w
                  where w.id = workout_id
                    and (w.user_id = (select auth.uid()) or public.es_admin())));
create policy workout_sets_insert on public.workout_sets
  for insert to authenticated
  with check (exists (select 1 from public.workouts w
                       where w.id = workout_id and w.user_id = (select auth.uid())));
create policy workout_sets_update on public.workout_sets
  for update to authenticated
  using (exists (select 1 from public.workouts w
                  where w.id = workout_id and w.user_id = (select auth.uid())))
  with check (exists (select 1 from public.workouts w
                       where w.id = workout_id and w.user_id = (select auth.uid())));
create policy workout_sets_delete on public.workout_sets
  for delete to authenticated
  using (exists (select 1 from public.workouts w
                  where w.id = workout_id and w.user_id = (select auth.uid())));
