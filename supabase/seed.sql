-- Local development data only (runs on `supabase db reset`).
-- Real schedules, fields and scores come from the golf data feed in phase 3.

insert into public.tournaments (provider_id, name, season, start_date, end_date, course, is_major, has_cut, status) values
  ('dev-2027-01', 'The Sentry (sample)',               2027, '2027-01-07', '2027-01-10', 'Plantation Course at Kapalua', false, false, 'scheduled'),
  ('dev-2027-02', 'Sony Open in Hawaii (sample)',      2027, '2027-01-14', '2027-01-17', 'Waialae Country Club',         false, true,  'scheduled'),
  ('dev-2027-03', 'The American Express (sample)',     2027, '2027-01-21', '2027-01-24', 'PGA West',                     false, true,  'scheduled'),
  ('dev-2027-04', 'Farmers Insurance Open (sample)',   2027, '2027-01-28', '2027-01-31', 'Torrey Pines',                 false, true,  'scheduled'),
  ('dev-2027-05', 'The Players Championship (sample)', 2027, '2027-03-11', '2027-03-14', 'TPC Sawgrass',                 false, true,  'scheduled'),
  ('dev-2027-06', 'Masters Tournament (sample)',       2027, '2027-04-08', '2027-04-11', 'Augusta National',             true,  true,  'scheduled')
on conflict (provider_id) do nothing;

insert into public.players (provider_id, first_name, last_name, country, is_rookie, owgr) values
  ('dev-p01', 'Alex',   'Rivers',   'USA', false, 1),
  ('dev-p02', 'Ben',    'Calloway', 'NIR', false, 2),
  ('dev-p03', 'Carlos', 'Mendez',   'ESP', false, 3),
  ('dev-p04', 'Daniel', 'Okafor',   'ENG', false, 4),
  ('dev-p05', 'Ethan',  'Park',     'KOR', false, 5),
  ('dev-p06', 'Felix',  'Larsen',   'NOR', true,  40),
  ('dev-p07', 'Gabe',   'Turner',   'USA', true,  55),
  ('dev-p08', 'Hiro',   'Tanaka',   'JPN', true,  72)
on conflict (provider_id) do nothing;
