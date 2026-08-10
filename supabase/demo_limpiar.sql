-- =====================================================================
-- GymAI · Borrar los datos de demostración
--
-- Elimina únicamente a los participantes marcados como is_demo.
-- Las cuentas reales y el catálogo no se tocan: el borrado en cascada
-- desde auth.users se lleva sesiones, series, pesos, comidas y plan.
--
-- Correr esto ANTES de sacar cualquier conclusión del estudio.
-- =====================================================================

-- Qué se va a borrar
select p.display_name, p.is_demo,
       (select count(*) from public.workouts w where w.user_id = p.id) as sesiones
from public.profiles p
where p.is_demo;

-- Borrado
delete from auth.users u
 using public.profiles p
 where p.id = u.id and p.is_demo;

-- Comprobación: no debe quedar ninguno
select count(*) filter (where is_demo) as demos_restantes,
       count(*)                        as perfiles_totales
from public.profiles;
