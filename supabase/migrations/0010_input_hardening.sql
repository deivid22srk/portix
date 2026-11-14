-- ============================================================================
-- PORTIX — 0010: endurecimento de entrada (proativo)
--
-- * search_games: limita o termo de busca a 120 caracteres (evita consultas
--   patológicas em pg_trgm/similarity).
-- * profiles.display_name: limite de tamanho.
-- Idempotente.
-- ============================================================================

create or replace function public.search_games(
  p_query      text    default null,
  p_platform   text    default null,
  p_genre      text    default null,
  p_free_only  boolean default false,
  p_needs_rom  boolean default false,
  p_sort       text    default 'relevance',
  p_limit      int     default 24,
  p_offset     int     default 0
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
with q as (
  select left(nullif(trim(coalesce(p_query, '')), ''), 120) as term
)
select jsonb_build_object(
  'items', coalesce(jsonb_agg(to_jsonb(t) - 'total_count' - 'score'), '[]'::jsonb),
  'total', coalesce(max(t.total_count), 0)
)
from (
  select c.*,
         count(*) over() as total_count,
         case when (select term from q) is not null
              then extensions.similarity(c.title, (select term from q))
              else 0 end as score
  from public.game_cards c, q
  where (
      q.term is null
      or c.title ilike '%' || q.term || '%'
      or coalesce(c.developer, '') ilike '%' || q.term || '%'
      or coalesce(c.genre, '') ilike '%' || q.term || '%'
    )
    and (p_platform is null or p_platform = any(c.platform_slugs))
    and (p_genre is null or c.genre = p_genre)
    and (not coalesce(p_free_only, false) or c.is_free)
    and (not coalesce(p_needs_rom, false) or c.needs_rom)
  order by
    (case when p_sort = 'az' then c.title end) asc,
    (case when p_sort = 'recent' then c.released_on end) desc nulls last,
    (case when p_sort = 'year' then c.year end) desc nulls last,
    (case when p_sort = 'trending' then c.visit_count end) desc nulls last,
    score desc,
    c.visit_count desc,
    c.title asc
  limit least(greatest(p_limit, 1), 60)
  offset greatest(p_offset, 0)
) t;
$$;

grant execute on function public.search_games(text, text, text, boolean, boolean, text, integer, integer)
  to anon, authenticated;

-- profiles.display_name com tamanho limitado
alter table public.profiles
  drop constraint if exists profiles_display_name_len;
alter table public.profiles
  add constraint profiles_display_name_len check (char_length(display_name) <= 80);
