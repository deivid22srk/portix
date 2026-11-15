-- ============================================================================
-- PORTIX — 0021: adiciona Spore (port nativo para Android) ao catálogo
--
-- Fonte: projeto VinTeRuS/spore-re (recompilação estática de x86), com APKs
-- nas releases do GitHub. Cobre também as plataformas de origem em PC, que
-- ainda não existiam no catálogo (por isso a plataforma "pc" é criada aqui).
--
-- Idempotente: pode ser aplicada mais de uma vez sem duplicar nada.
-- ============================================================================

-- ------------------------------------------------------------- plataforma PC
insert into public.platforms (slug, name, full_name, kind, sort_order)
values ('pc', 'PC', 'Microsoft Windows', 'other', 5)
on conflict (slug) do update set
  name       = excluded.name,
  full_name  = excluded.full_name,
  kind       = excluded.kind,
  sort_order = excluded.sort_order;

-- --------------------------------------------------------------------- jogo
insert into public.games (
  slug, title, year, genre, description, cover_url, developer,
  platforms, platform_slugs, is_free, needs_rom, released_on, last_activity_on
)
values (
  'spore',
  'Spore',
  2008,
  'Simulation',
  'Port nativo de Spore (com Galactic Adventures) para Android: SporeApp.exe é recompilado estaticamente de x86 para C e roda sobre uma camada Win32/D3D9 própria (SDL2 + DXVK), sem emulador e sem Wine. Exige Android 10+ em arm64 e uma cópia própria do Spore (GOG Collection 3.1.0.22): copie as pastas Data, DataEP1, SporebinEP1 e bp1content para o armazenamento interno, em /Spore. Os controles de toque mudam a cada estágio, com opções de resolução, nitidez, limite de FPS e layout dos botões. Projeto em estágio inicial: alguns perfis com mods podem travar e ainda não há entrada para Space Adventures.',
  'https://cdn.mobygames.com/covers/10836988-spore-windows-front-cover.jpg',
  'VinTeRuS',
  array['PC'],
  array['pc'],
  true,
  true,
  '2008-09-07',
  current_date
)
on conflict (slug) do update set
  title            = excluded.title,
  year             = excluded.year,
  genre            = excluded.genre,
  description      = excluded.description,
  cover_url        = excluded.cover_url,
  developer        = excluded.developer,
  platforms        = excluded.platforms,
  platform_slugs   = excluded.platform_slugs,
  is_free          = excluded.is_free,
  needs_rom        = excluded.needs_rom,
  released_on      = excluded.released_on,
  last_activity_on = excluded.last_activity_on;

-- --------------------------------------------------------------------- port
insert into public.ports (
  port_key, game_id, platform_id, project, source, url, developer, version,
  last_update, date_added, needs_game_files, needs_game_files_note, works,
  controller_support, notes, visits, sort_index
)
select
  'spore-re',
  g.id,
  p.id,
  'Spore RE (recompilação x86)',
  'Free (Github)',
  'https://github.com/VinTeRuS/spore-re',
  'VinTeRuS',
  'v0.1.3',
  date '2026-11-15',
  date '2026-11-15',
  true,
  'Requer uma cópia própria do Spore (GOG Collection 3.1.0.22, SporebinEP1/SporeApp.exe). Copie Data, DataEP1, SporebinEP1 e bp1content para /sdcard/Spore.',
  'untested',
  null,
  'Duas builds: spore.apk (Vulkan 1.3) e spore-vk11.apk (Vulkan 1.1, para GPUs mais antigas).',
  0,
  0
from public.games g
join public.platforms p on p.slug = 'pc'
where g.slug = 'spore'
on conflict (port_key) do update set
  game_id               = excluded.game_id,
  platform_id           = excluded.platform_id,
  project               = excluded.project,
  source                = excluded.source,
  url                   = excluded.url,
  developer             = excluded.developer,
  version               = excluded.version,
  last_update           = excluded.last_update,
  needs_game_files      = excluded.needs_game_files,
  needs_game_files_note = excluded.needs_game_files_note,
  works                 = excluded.works,
  notes                 = excluded.notes;

-- --------------------------------------------------- contadores do catálogo
update public.games g
set port_count = sub.total
from (
  select game_id, count(*)::int as total
  from public.ports
  group by game_id
) sub
where sub.game_id = g.id
  and g.port_count <> sub.total;
