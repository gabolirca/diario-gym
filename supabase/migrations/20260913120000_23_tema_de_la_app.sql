-- =====================================================================
-- GymAI · 23 · Tema de la app
--
-- Cada persona elige con qué colores ve la app. Se guarda en el perfil,
-- no solo en el dispositivo, para que al entrar desde otro teléfono la
-- encuentre como la dejó.
--
-- Es apariencia y nada más: no toca ningún dato del estudio, no cambia el
-- programa de entrenamiento y no entra en el análisis. Se deja explícito
-- aquí porque una columna en profiles invita a pensar que sí.
-- =====================================================================

alter table public.profiles add column if not exists theme text not null default 'verde'
  check (theme in ('verde','orquidea','indigo'));

comment on column public.profiles.theme is
  'Paleta de colores elegida por la persona. Viaja con la cuenta para que la app se vea igual en cualquier dispositivo. Es solo apariencia: no toca ningún dato del estudio ni entra en el análisis.';
