-- =====================================================================
-- GymAI · 07 · Row Level Security
-- Cada usuario solo ve y escribe sus propios datos.
-- El catálogo global (owner_id null) es de lectura para todos.
-- =====================================================================

-- Las vistas deben respetar las políticas de quien consulta, no del creador
alter view public.v_body_fat          set (security_invoker = on);
alter view public.v_working_sets      set (security_invoker = on);
alter view public.v_exercise_sessions set (security_invoker = on);
alter view public.v_ml_dataset        set (security_invoker = on);
alter view public.v_weekly_volume     set (security_invoker = on);
alter view public.v_personal_records  set (security_invoker = on);

alter table public.profiles          enable row level security;
alter table public.exercises         enable row level security;
alter table public.routines          enable row level security;
alter table public.routine_exercises enable row level security;
alter table public.workouts          enable row level security;
alter table public.workout_sets      enable row level security;
alter table public.body_weights      enable row level security;
alter table public.body_measures     enable row level security;
alter table public.sleep_logs        enable row level security;
alter table public.swims             enable row level security;
alter table public.nutrition_logs    enable row level security;
alter table public.plan_targets      enable row level security;
alter table public.predictions       enable row level security;
alter table public.model_versions    enable row level security;

-- ---------- profiles ----------
create policy profiles_select_own on public.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy profiles_update_own on public.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);

-- ---------- catálogo: global legible, propio editable ----------
create policy exercises_select on public.exercises
  for select to authenticated using (owner_id is null or owner_id = (select auth.uid()));
create policy exercises_write on public.exercises
  for all to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy routines_select on public.routines
  for select to authenticated using (owner_id is null or owner_id = (select auth.uid()));
create policy routines_write on public.routines
  for all to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy routine_exercises_select on public.routine_exercises
  for select to authenticated using (exists (
    select 1 from public.routines r
     where r.id = routine_id and (r.owner_id is null or r.owner_id = (select auth.uid()))));
create policy routine_exercises_write on public.routine_exercises
  for all to authenticated using (exists (
    select 1 from public.routines r where r.id = routine_id and r.owner_id = (select auth.uid())))
  with check (exists (
    select 1 from public.routines r where r.id = routine_id and r.owner_id = (select auth.uid())));

-- ---------- tablas con user_id directo ----------
do $$
declare t text;
begin
  foreach t in array array['workouts','body_weights','body_measures','sleep_logs',
                           'swims','nutrition_logs','plan_targets','predictions']
  loop
    execute format(
      'create policy %1$s_own on public.%1$s for all to authenticated
         using ((select auth.uid()) = user_id)
         with check ((select auth.uid()) = user_id)', t);
  end loop;
end $$;

-- ---------- workout_sets: hereda del workout padre ----------
create policy workout_sets_own on public.workout_sets
  for all to authenticated
  using (exists (select 1 from public.workouts w
                  where w.id = workout_id and w.user_id = (select auth.uid())))
  with check (exists (select 1 from public.workouts w
                       where w.id = workout_id and w.user_id = (select auth.uid())));

-- ---------- model_versions: lectura para todos, escritura solo desde el backend ----------
create policy model_versions_read on public.model_versions
  for select to authenticated using (true);
