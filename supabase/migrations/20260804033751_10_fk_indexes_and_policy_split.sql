-- =====================================================================
-- GymAI · 10 · Índices de llaves foráneas y separación de políticas
-- Las políticas FOR ALL duplicaban la evaluación en cada SELECT.
-- Se separan: una sola política de lectura por tabla.
-- =====================================================================

create index if not exists predictions_actual_set_idx    on public.predictions (actual_set_id);
create index if not exists predictions_exercise_idx      on public.predictions (exercise_id);
create index if not exists predictions_model_version_idx on public.predictions (model_version_id);
create index if not exists routine_exercises_exercise_idx on public.routine_exercises (exercise_id);
create index if not exists workouts_routine_idx          on public.workouts (routine_id);

-- ---------- exercises ----------
drop policy exercises_write on public.exercises;
create policy exercises_insert on public.exercises
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy exercises_update on public.exercises
  for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy exercises_delete on public.exercises
  for delete to authenticated using (owner_id = (select auth.uid()));

-- ---------- routines ----------
drop policy routines_write on public.routines;
create policy routines_insert on public.routines
  for insert to authenticated with check (owner_id = (select auth.uid()));
create policy routines_update on public.routines
  for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy routines_delete on public.routines
  for delete to authenticated using (owner_id = (select auth.uid()));

-- ---------- routine_exercises ----------
drop policy routine_exercises_write on public.routine_exercises;
create policy routine_exercises_insert on public.routine_exercises
  for insert to authenticated with check (exists (
    select 1 from public.routines r where r.id = routine_id and r.owner_id = (select auth.uid())));
create policy routine_exercises_update on public.routine_exercises
  for update to authenticated
  using (exists (select 1 from public.routines r where r.id = routine_id and r.owner_id = (select auth.uid())))
  with check (exists (select 1 from public.routines r where r.id = routine_id and r.owner_id = (select auth.uid())));
create policy routine_exercises_delete on public.routine_exercises
  for delete to authenticated using (exists (
    select 1 from public.routines r where r.id = routine_id and r.owner_id = (select auth.uid())));
