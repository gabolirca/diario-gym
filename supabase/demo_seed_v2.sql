-- =====================================================================
-- GymAI · Participantes inventados para la demostración (solo v2)
--
-- Cinco perfiles con seis semanas de historial: déficit, recomposición,
-- volumen, mantenimiento y uno irregular que falta a entrenar y casi no
-- registra el RIR. El irregular importa: una demostración donde todos
-- cumplen no enseña nada, y el panel existe justamente para detectar a
-- quien se está cayendo del estudio.
--
-- Por qué seis semanas y no dos: el modelo necesita al menos tres
-- sesiones del MISMO ejercicio para predecir. Con una rutina de cuatro
-- días, dos semanas dan dos sesiones por ejercicio y no alcanza. Seis
-- semanas dan seis, y además una curva de peso de dos semanas es casi
-- todo ruido: no se distingue una tendencia de una comida salada.
--
-- Todos van con is_demo=true y fecha de caducidad a 30 días. El panel los
-- enseña con el aviso de datos inventados y pg_cron los borra solo.
--
-- Para borrarlos antes:  select private.borrar_demos_ahora();
-- =====================================================================

do $seed$
declare
  hoy            date := current_date;
  inicio         date := current_date - 42;      -- seis semanas
  caduca         timestamptz := now() + interval '30 days';

  -- nombre, correo, sexo, edad, estatura, peso inicial, objetivo, meta de peso,
  -- cintura inicial, kg/semana de peso, cm/semana de cintura, % de fuerza por semana,
  -- constancia (probabilidad de entrenar), probabilidad de registrar el RIR
  perfiles       jsonb := jsonb_build_array(
    jsonb_build_object('n','Ana R.',   'e','demo.ana@gymai.test',   's','F','ed',24,'h',163,'p0',72.0,
                       'g','fat_loss',   'meta',65.0,'c0',86.0,'dpeso',-0.55,'dcin',-0.45,'dfza',0.004,'const',0.92,'prir',0.95),
    jsonb_build_object('n','Beto M.',  'e','demo.beto@gymai.test',  's','M','ed',27,'h',175,'p0',78.5,
                       'g','recomp',     'meta',75.0,'c0',92.0,'dpeso',-0.12,'dcin',-0.28,'dfza',0.007,'const',0.90,'prir',0.90),
    jsonb_build_object('n','Caro L.',  'e','demo.caro@gymai.test',  's','F','ed',22,'h',168,'p0',58.0,
                       'g','muscle_gain','meta',63.0,'c0',70.0,'dpeso', 0.28,'dcin', 0.12,'dfza',0.013,'const',0.95,'prir',0.93),
    jsonb_build_object('n','Diego P.', 'e','demo.diego@gymai.test', 's','M','ed',31,'h',180,'p0',84.0,
                       'g','strength',   'meta',84.0,'c0',94.0,'dpeso', 0.02,'dcin',-0.05,'dfza',0.010,'const',0.88,'prir',0.88),
    jsonb_build_object('n','Emi V.',   'e','demo.emi@gymai.test',   's','M','ed',20,'h',172,'p0',69.0,
                       'g','muscle_gain','meta',75.0,'c0',80.0,'dpeso', 0.06,'dcin', 0.04,'dfza',0.002,'const',0.45,'prir',0.35)
  );

  rutinas        text[] := array['upperA','lowerA','upperB','lowerB'];
  perfil         jsonb;
  uid            uuid;
  idx            int;
  dia            date;
  semana         numeric;
  rut            text;
  rid            bigint;
  wid            bigint;
  re             record;
  serie          int;
  base           numeric;
  carga          numeric;
  reps           int;
  rir_real       numeric;
  peso_dia       numeric;
  kcal_obj       int;
  kcal_real      int;
  n_ses          int;
  sembrado       int := 0;
begin
  -- Semilla fija: el mismo comando produce siempre los mismos datos.
  perform setseed(0.4242);

  for idx in 0 .. jsonb_array_length(perfiles) - 1 loop
    perfil := perfiles -> idx;
    uid := gen_random_uuid();

    -- ---------------- Cuenta ----------------
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change)
    values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
      perfil->>'e',
      extensions.crypt('demo-' || md5(random()::text), extensions.gen_salt('bf')),
      now() - interval '42 days', now() - interval '42 days', now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('display_name', perfil->>'n'),
      '', '', '', '');

    -- El disparador de la migración 01 ya creó el perfil; aquí se completa.
    update public.profiles set
      display_name = perfil->>'n',
      sex = perfil->>'s',
      birth_date = (hoy - ((perfil->>'ed')::int * 365 + 100))::date,
      height_cm = (perfil->>'h')::numeric,
      goal = perfil->>'g',
      initial_weight_kg = (perfil->>'p0')::numeric,
      target_weight_kg = (perfil->>'meta')::numeric,
      target_waist_cm = round(((perfil->>'c0')::numeric + (perfil->>'dcin')::numeric * 26), 1),
      training_days_per_week = 4,
      training_since = (inicio - ((12 + idx * 6) * 30))::date,
      plan_start = inicio,
      plan_weeks = 26,
      research_consent = true,
      onboarded_at = inicio::timestamptz,
      is_demo = true,
      demo_expires_at = caduca
    where id = uid;

    -- ---------------- Peso diario y comida ----------------
    kcal_obj := case perfil->>'g'
                  when 'fat_loss'    then 1750 + idx * 40
                  when 'muscle_gain' then 2600 + idx * 40
                  when 'recomp'      then 2150
                  else 2400 end;

    dia := inicio;
    while dia <= hoy loop
      semana := (dia - inicio) / 7.0;
      peso_dia := (perfil->>'p0')::numeric
                + (perfil->>'dpeso')::numeric * semana
                + (random() - 0.5) * 0.7;                    -- ruido de báscula

      -- Nadie se pesa todos los días; el irregular menos que nadie.
      if random() < (perfil->>'const')::numeric then
        insert into public.body_weights (user_id, measured_on, weight_kg)
        values (uid, dia, round(peso_dia, 1))
        on conflict do nothing;
      end if;

      if random() < (perfil->>'const')::numeric * 0.85 then
        kcal_real := kcal_obj + (random() * 500 - 250)::int;
        insert into public.nutrition_logs
          (user_id, logged_on, kcal, protein_g, carbs_g, fat_g, kcal_target, source)
        values (uid, dia, kcal_real,
                round((peso_dia * (1.7 + random() * 0.5))::numeric, 1),
                round((kcal_real * 0.42 / 4)::numeric, 1),
                round((kcal_real * 0.27 / 9)::numeric, 1),
                kcal_obj, 'manual')
        on conflict do nothing;
      end if;

      if random() < 0.75 then
        insert into public.sleep_logs (user_id, logged_on, hours)
        values (uid, dia, round((6.4 + random() * 2.2)::numeric, 1))
        on conflict do nothing;
      end if;

      -- Medidas los domingos
      if extract(dow from dia) = 0 then
        insert into public.body_measures (user_id, measured_on, waist_cm, neck_cm, chest_cm, arm_cm, thigh_cm)
        values (uid, dia,
                round(((perfil->>'c0')::numeric + (perfil->>'dcin')::numeric * semana + (random()-0.5)*0.5)::numeric, 1),
                round((case perfil->>'s' when 'F' then 32 else 38 end + random())::numeric, 1),
                round((case perfil->>'s' when 'F' then 88 else 100 end + semana * 0.15 + random())::numeric, 1),
                round((case perfil->>'s' when 'F' then 28 else 34 end + semana * 0.10 + random()*0.4)::numeric, 1),
                round((case perfil->>'s' when 'F' then 55 else 58 end + semana * 0.12 + random()*0.5)::numeric, 1))
        on conflict do nothing;
      end if;

      dia := dia + 1;
    end loop;

    -- ---------------- Entrenamientos ----------------
    -- Lunes, martes, jueves y viernes. La rutina rota entre las cuatro.
    n_ses := 0;
    dia := inicio;
    while dia <= hoy loop
      if extract(dow from dia) in (1, 2, 4, 5) then
        -- La constancia decide si esa sesión ocurrió
        if random() < (perfil->>'const')::numeric then
          semana := (dia - inicio) / 7.0;
          rut := rutinas[(n_ses % 4) + 1];
          select id into rid from public.routines where slug = rut and owner_id is null;

          insert into public.workouts
            (user_id, client_uid, performed_on, routine_id, session_rpe, duration_min, notes)
          values (uid, 'demo-' || uid || '-' || n_ses, dia, rid,
                  6 + (random() * 3)::int, 50 + (random() * 30)::int, null)
          returning id into wid;

          for re in
            select e.id as ex_id, e.slug, coalesce(e.load_increment_kg, 2.5) as inc,
                   re2.target_sets, re2.target_reps_min, re2.target_reps_max,
                   coalesce(re2.target_rir_min, 1) as rmin, coalesce(re2.target_rir_max, 3) as rmax,
                   re2.order_index
              from public.routine_exercises re2
              join public.exercises e on e.id = re2.exercise_id
             where re2.routine_id = rid
             order by re2.order_index
          loop
            -- Carga base del ejercicio, escalada por la persona y por el tiempo.
            base := case
                      when re.slug in ('peso-muerto') then 70
                      when re.slug in ('sentadilla-hack','prensa') then 60
                      when re.slug in ('press-banca-inclinado','remo-alto-abierto') then 35
                      when re.slug in ('press-militar-barra','jalon-al-pecho','curl-femoral',
                                       'extension-cuadriceps','pantorrilla') then 30
                      when re.slug in ('remo-unilateral-mancuerna','sentadilla-goblet','abductor',
                                       'extension-triceps-polea','curl-biceps-barra') then 18
                      when re.slug in ('dominadas','fondos-paralelas','hiperextension-baja') then 0
                      else 9
                    end
                    * (case perfil->>'s' when 'F' then 0.62 else 1.0 end)
                    * (0.85 + idx * 0.07);

            carga := base * (1 + (perfil->>'dfza')::numeric * semana);
            -- Al gimnasio se va con los discos que hay
            carga := greatest(re.inc, round(carga / re.inc) * re.inc);

            for serie in 1 .. re.target_sets loop
              reps := re.target_reps_min
                    + (random() * (re.target_reps_max - re.target_reps_min + 1))::int;
              reps := least(reps, re.target_reps_max);
              -- El RIR baja conforme avanzan las series: cansa
              rir_real := greatest(0, round(re.rmax - (serie - 1) * 0.8 + (random() - 0.5)));

              insert into public.workout_sets
                (workout_id, exercise_id, set_index, weight_kg, reps, rir, is_warmup)
              values (wid, re.ex_id, serie,
                      -- Las últimas series suelen bajar un poco de peso
                      greatest(re.inc, carga - (case when serie = re.target_sets and random() < 0.3
                                                     then re.inc else 0 end)),
                      reps,
                      -- El irregular casi no registra el RIR: es el hueco que
                      -- el panel tiene que ser capaz de detectar.
                      case when random() < (perfil->>'prir')::numeric then rir_real else null end,
                      false);
            end loop;
          end loop;

          n_ses := n_ses + 1;
        end if;
      end if;
      dia := dia + 1;
    end loop;

    sembrado := sembrado + 1;
    raise notice 'Sembrado % (%): % sesiones', perfil->>'n', perfil->>'g', n_ses;
  end loop;

  raise notice 'Listo: % participantes de prueba, caducan el %', sembrado, caduca::date;
end
$seed$;

-- ---------------------------------------------------------------------
-- Borrarlos a mano, sin esperar a que caduquen
-- ---------------------------------------------------------------------
create or replace function private.borrar_demos_ahora()
returns integer
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare n integer;
begin
  with fuera as (
    delete from auth.users u using public.profiles p
     where p.id = u.id and p.is_demo
    returning u.id)
  select count(*) into n from fuera;
  return n;
end;
$$;

revoke all on function private.borrar_demos_ahora() from public, anon, authenticated;
