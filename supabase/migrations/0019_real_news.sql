-- ============================================================================
-- PORTIX — 0019: notícias reais (artigos)
--
-- Substitui o feed "sintético" (derivado de jogos) por uma tabela de artigos
-- de notícias de verdade. Inclui o seed da notícia do port não oficial de
-- DOOM (2016) para Android.
--
-- Idempotente: pode ser aplicada mais de uma vez sem duplicar o artigo.
-- ============================================================================

create table if not exists public.news_articles (
  id             uuid primary key default gen_random_uuid(),
  slug           text not null unique,
  category       text not null default 'Ports',
  title          text not null,
  title_original text,
  author         text,
  summary        text not null default '',
  key_points     jsonb not null default '[]'::jsonb,
  cover_url      text,
  source_name    text,
  source_url     text,
  project_url    text,
  published_at   timestamptz not null default now(),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists news_articles_published_idx
  on public.news_articles (published_at desc);

alter table public.news_articles enable row level security;

-- Leitura pública; a escrita é feita pela administração (service role), que
-- ignora a RLS. Nenhuma política de escrita para clientes anônimos.
drop policy if exists "news_public_read" on public.news_articles;
create policy "news_public_read" on public.news_articles
  for select to anon, authenticated using (true);

grant select on public.news_articles to anon, authenticated;

-- --------------------------------------------------------------- feed
create or replace function public.news_feed(p_limit int default 20, p_offset int default 0)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
select jsonb_build_object(
  'items', coalesce(
    jsonb_agg(to_jsonb(t) - 'total_count' order by t.published_at desc),
    '[]'::jsonb
  ),
  'total', coalesce(max(t.total_count), 0)
)
from (
  select n.id, n.slug, n.category, n.title, n.title_original, n.author,
         n.summary, n.key_points, n.cover_url, n.source_name, n.source_url,
         n.project_url, n.published_at,
         count(*) over() as total_count
  from public.news_articles n
  order by n.published_at desc
  limit least(greatest(p_limit, 1), 50)
  offset greatest(p_offset, 0)
) t;
$$;

grant execute on function public.news_feed(int, int) to anon, authenticated;

-- ------------------------------------------------------- artigo individual
create or replace function public.news_article(p_slug text)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
select to_jsonb(n)
from public.news_articles n
where n.slug = p_slug;
$$;

grant execute on function public.news_article(text) to anon, authenticated;

-- ---------------------------------------------------------------- seed
insert into public.news_articles (
  slug, category, title, title_original, author, summary, key_points,
  cover_url, source_name, source_url, project_url, published_at
)
values (
  'doom-2016-port-android',
  'Ports',
  'DOOM (2016) recebe port não oficial para Android',
  'DOOM (2016) gets APK port for Android',
  'Dario Coutinho',
  'Um projeto independente chamado DOOM Mobile está adaptando DOOM (2016) para Android com base na versão de Nintendo Switch. A abordagem executa código ARM64 no celular e converte chamadas gráficas NVN para Vulkan, sem emular tradicionalmente o processador do console. O port ainda é experimental e não distribui os arquivos comerciais do jogo.',
  '[
    "Em aparelhos com Snapdragon 8 Gen 3, o desenvolvedor relata cerca de 50 a 60 FPS em boa parte da campanha, com quedas em áreas mais exigentes.",
    "A adaptação oferece controles na tela, suporte a controles Bluetooth e USB e opções de resolução e desempenho.",
    "O projeto é não oficial, está em desenvolvimento e não inclui modo multiplayer.",
    "Para usar o port, é necessário possuir uma cópia compatível de DOOM (2016) para Nintendo Switch e preparar os arquivos conforme as instruções do projeto."
  ]'::jsonb,
  'https://www.mobilegamer.com.br/wp-content/uploads/2026/11/doom-2016-port-nativo-scaled.webp',
  'Mobile Gamer Brasil',
  'https://www.mobilegamer.com.br/en/2026/11/doom-2016-gets-apk-port-for-android.html',
  'https://github.com/Desm0nt/doom-port',
  '2026-11-05T12:00:00-03:00'
)
on conflict (slug) do update set
  category       = excluded.category,
  title          = excluded.title,
  title_original = excluded.title_original,
  author         = excluded.author,
  summary        = excluded.summary,
  key_points     = excluded.key_points,
  cover_url      = excluded.cover_url,
  source_name    = excluded.source_name,
  source_url     = excluded.source_url,
  project_url    = excluded.project_url,
  published_at   = excluded.published_at,
  updated_at     = now();
