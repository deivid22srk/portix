-- ============================================================================
-- PORTIX — 0022: notícia do port nativo aprimorado de The Witcher 3
--
-- Fonte: Reddit (r/AndroidNativePorts). Capa hospedada publicamente no Google
-- Drive (imagem PNG 1600x720).
-- Idempotente: reaplicar atualiza a notícia sem duplicar.
-- ============================================================================

insert into public.news_articles (
  slug, category, title, title_original, author, summary, key_points,
  cover_url, source_name, source_url, project_url, published_at
)
values (
  'witcher-3-native-android-enhanced',
  'Ports',
  'The Witcher 3 ganha port nativo aprimorado para Android, com suporte a mods',
  'Witcher 3 - Native [Enhanced]: Extended Look at the Native Android Port, Now With Full Mod Support and Upgraded Graphics',
  'u/Intelligent_Drag4310, com informações atribuídas a REALGHO5TLY',
  'Uma nova atualização do projeto Witcher 3 - Native [Enhanced] detalha recursos gráficos, suporte a mods e controles adaptados para Android. Segundo o desenvolvedor, o jogo roda nativamente no processador do celular, sem emulador ou camada de tradução. O port ainda está em testes fechados e não tem lançamento público.',
  '[
    "O projeto promete suporte a texturas aprimoradas, resolução de até 3x a interna, antialiasing, upscaling e opções para diferentes proporções de tela.",
    "O desenvolvedor afirma que o jogo executa código nativo no celular e que a API gráfica NVN foi reconstruída sobre Vulkan.",
    "De acordo com os testes divulgados pelo projeto, o port busca manter 30 FPS; um recurso opcional de geração de quadros poderia elevar a exibição para 50 a 60 FPS.",
    "A atualização anuncia suporte a mods importados como arquivos ZIP ou pastas, além de controles touchscreen configuráveis, giroscópio e compatibilidade com teclado e controles físicos.",
    "O projeto foi testado em aparelhos Snapdragon e em um Samsung Galaxy S24 com Exynos 2400. A compatibilidade com GPUs Mali ainda precisa de mais testes.",
    "A versão está em testes fechados. O desenvolvedor cita uma próxima fase de testes e um lançamento público futuro, sem informar uma data.",
    "É necessário fornecer os próprios arquivos do jogo para Nintendo Switch, incluindo jogo-base, atualização 4.04b e DLCs. O projeto afirma não distribuir esses arquivos."
  ]'::jsonb,
  'https://drive.google.com/uc?export=download&id=1hcri1o3dHMpsFDPspaV-i0J3zbbsKOkA',
  'Reddit — r/AndroidNativePorts',
  'https://www.reddit.com/r/AndroidNativePorts/comments/1xwvaii/witcher_3_native_enhanced_extended_look_at_the/',
  'https://discord.gg/vVWdUfj78',
  '2026-11-15T12:00:00-03:00'
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
