-- =====================================================================
-- GymAI · 09 · Endurecimiento de funciones
-- Fija search_path y quita EXECUTE público de las funciones de trigger:
-- se ejecutan por el trigger, nadie debe poder llamarlas vía la API REST.
-- =====================================================================

alter function public.touch_updated_at()      set search_path = public, pg_temp;
alter function public.stamp_consent()         set search_path = public, pg_temp;
alter function public.handle_new_user()       set search_path = public, pg_temp;
alter function public.close_prediction_loop() set search_path = public, pg_temp;

revoke all on function public.touch_updated_at()      from public, anon, authenticated;
revoke all on function public.stamp_consent()         from public, anon, authenticated;
revoke all on function public.handle_new_user()       from public, anon, authenticated;
revoke all on function public.close_prediction_loop() from public, anon, authenticated;
