import 'package:flutter/widgets.dart';

// Textos do app em pt-BR e en, sem codegen: menos partes móveis no CI,
// tipagem direta e troca de idioma instantânea pelo MaterialApp.
class L10n {
  const L10n(this.locale);

  final Locale locale;

  bool get isEn => locale.languageCode == 'en';

  String _t(String pt, String en) => isEn ? en : pt;

  // ---------------------------------------------------------------- marca
  String get appName => 'PORTIX';
  String get tagline => _t('Seus consoles. No seu bolso.', 'Your consoles. In your pocket.');

  // ------------------------------------------------------------ navegação
  String get navHome => _t('Início', 'Home');
  String get navSearch => _t('Explorar', 'Explore');
  String get navLibrary => _t('Biblioteca', 'Library');
  String get navDownloads => _t('Downloads', 'Downloads');
  String get navProfile => _t('Perfil', 'Profile');

  // ------------------------------------------------------------------ home
  String get greetingMorning => _t('Bom dia', 'Good morning');
  String get greetingAfternoon => _t('Boa tarde', 'Good afternoon');
  String get greetingEvening => _t('Boa noite', 'Good evening');
  String get homeTitle => _t('O que vamos jogar?', 'What are we playing?');
  String get homeSubtitle => _t('Ports de clássicos e novos, prontos para o Android.',
      'Ports of classics and new hits, ready for Android.');
  String get sectionTrending => _t('Em alta agora', 'Trending now');
  String get sectionRecent => _t('Novos lançamentos', 'New releases');
  String get sectionClassics => _t('Clássicos eternos', 'Timeless classics');
  String get sectionFree => _t('Grátis e aberto', 'Free and open');
  String get sectionPlatforms => _t('Por plataforma', 'By platform');
  String get sectionGenres => _t('Por gênero', 'By genre');
  String get seeAll => _t('Ver tudo', 'See all');
  String get searchShort => _t('Busque por jogo, gênero ou dev', 'Search by game, genre or dev');
  String get catalogStatsHint => _t('catálogo aberto atualizado toda semana', 'open catalog updated weekly');

  // ---------------------------------------------------------------- busca
  String get searchTitle => _t('Explorar', 'Explore');
  String get searchHint => _t('Buscar jogos, gêneros, devs', 'Search games, genres, devs');
  String get filters => _t('Filtros', 'Filters');
  String get filterPlatform => _t('Plataforma', 'Platform');
  String get filterGenre => _t('Gênero', 'Genre');
  String get filterFree => _t('Somente grátis', 'Free only');
  String get filterRom => _t('Precisa de arquivos', 'Needs game files');
  String get sortLabel => _t('Ordenar', 'Sort');
  String get sortTrending => _t('Em alta', 'Trending');
  String get sortRecent => _t('Recentes', 'Recent');
  String get sortAz => 'A–Z';
  String get sortYear => _t('Mais novos', 'Newest');
  String get apply => _t('Aplicar', 'Apply');
  String get reset => _t('Limpar', 'Reset');
  String get all => _t('Tudo', 'All');
  String get noResultsTitle => _t('Nada por aqui', 'Nothing here');
  String get noResultsBody => _t('Nenhum port combina com esses filtros. Tente outra busca.',
      'No port matches these filters. Try another search.');
  String get recentSearches => _t('Buscas recentes', 'Recent searches');
  String get clearHistory => _t('Limpar histórico', 'Clear history');

  // -------------------------------------------------------------- detalhes
  String get install => _t('Instalar', 'Install');
  String get download => _t('Baixar', 'Download');
  String get continueAction => _t('Continuar', 'Continue');
  String get open => _t('Abrir', 'Open');
  String get installedLabel => _t('Instalado', 'Installed');
  String get addToLibrary => _t('Biblioteca', 'Library');
  String get inLibrary => _t('Na biblioteca', 'In library');
  String get favoriteTooltip => _t('Favoritar', 'Add to wishlist');
  String get unfavoriteTooltip => _t('Remover dos favoritos', 'Remove from wishlist');
  String get share => _t('Compartilhar', 'Share');
  String get linkCopied => _t('Link copiado', 'Link copied');
  String get portsTitle => _t('Ports disponíveis', 'Available ports');
  String get requirements => _t('Requisitos', 'Requirements');
  String get synopsis => _t('Sobre o jogo', 'About the game');
  String get readMore => _t('Ler mais', 'Read more');
  String get readLess => _t('Ler menos', 'Show less');
  String get releaseYear => _t('Ano', 'Year');
  String get developer => _t('Desenvolvedor', 'Developer');
  String get genreLabel => _t('Gênero', 'Genre');
  String get platformsLabel => _t('Plataformas', 'Platforms');
  String get portVersion => _t('Versão', 'Version');
  String get portUpdated => _t('Atualizado', 'Updated');
  String get portSource => _t('Fonte', 'Source');
  String get openSource => _t('Abrir fonte', 'Open source');
  String get noLink => _t('Sem link', 'No link');
  String get needsFiles => _t('Arquivos do jogo', 'Game files');
  String get needsFilesYes => _t('Necessários', 'Required');
  String get needsFilesNo => _t('Não precisa', 'Not required');
  String get controllerSupport => _t('Controle', 'Controller');
  String get notInformed => _t('Não informado', 'Not informed');
  String get worksYes => _t('Funciona', 'Works');
  String get worksNo => _t('Não funciona', 'Broken');
  String get worksUntested => _t('Não testado', 'Untested');
  String get worksBug => _t('Com bugs', 'Bugs');
  String get worksPartial => _t('Parcial', 'Partial');
  String get relatedTitle => _t('Você também pode gostar', 'You may also like');
  String get reviewsTitle => _t('Avaliações', 'Reviews');
  String get noReviews => _t('Ainda sem avaliações. Seja o primeiro.', 'No reviews yet. Be the first.');
  String get rateGame => _t('Avaliar', 'Rate');
  String get yourRating => _t('Sua nota', 'Your rating');
  String get reviewHint => _t('Conte como o port roda (opcional)', 'Tell us how the port runs (optional)');
  String get send => _t('Enviar', 'Send');
  String get reviewSent => _t('Avaliação publicada', 'Review published');
  String get newGame => _t('Novo', 'New');
  String get visits => _t('visitas', 'visits');

  // ------------------------------------------------------------ downloads
  String get downloadsTitle => _t('Downloads', 'Downloads');
  String get downloadsSubtitle => _t('Fila simulada, com pausa e retomada.', 'Simulated queue with pause and resume.');
  String get downloadEmpty => _t('Nada na fila', 'Queue is empty');
  String get downloadEmptyBody => _t('Abra um jogo e toque em Instalar para começar.',
      'Open a game and tap Install to start.');
  String get activeDownloads => _t('Em andamento', 'In progress');
  String get completedDownloads => _t('Concluídos', 'Completed');
  String get pause => _t('Pausar', 'Pause');
  String get resume => _t('Retomar', 'Resume');
  String get cancel => _t('Cancelar', 'Cancel');
  String get remove => _t('Remover', 'Remove');
  String get clearCompleted => _t('Limpar concluídos', 'Clear completed');
  String get downloadDone => _t('Download concluído', 'Download complete');
  String get downloadStarted => _t('Download iniciado', 'Download started');
  String get viewDownloads => _t('Ver downloads', 'View downloads');
  String get statusQueued => _t('Na fila', 'Queued');
  String get statusPaused => _t('Pausado', 'Paused');
  String get statusDone => _t('Concluído', 'Done');
  String get statusFailed => _t('Falhou', 'Failed');

  // ------------------------------------------------------------- biblioteca
  String get libraryTitle => _t('Biblioteca', 'Library');
  String get addedToLibrary => _t('Adicionado à biblioteca', 'Added to library');
  String get removedFromLibrary => _t('Removido da biblioteca', 'Removed from library');
  String get ratingRequired => _t('Escolha uma nota de 1 a 5', 'Pick a rating from 1 to 5');
  String get freeBadge => _t('Grátis', 'Free');
  String get libraryEmpty => _t('Sua biblioteca está vazia', 'Your library is empty');
  String get libraryEmptyBody => _t('Adicione jogos pela página de detalhes ou instale um port.',
      'Add games from detail pages or install a port.');
  String get explore => _t('Explorar catálogo', 'Explore catalog');
  String get wishlistTitle => _t('Lista de desejos', 'Wishlist');
  String get wishlistEmpty => _t('Nenhum favorito ainda', 'No favorites yet');
  String get wishlistEmptyBody => _t('Toque no coração de um jogo para guardar aqui.',
      "Tap a game's heart to save it here.");

  // ---------------------------------------------------------------- perfil
  String get profileTitle => _t('Perfil', 'Profile');
  String get player => _t('Jogador', 'Player');
  String get anonymousSession => _t('Sessão anônima sincronizada', 'Anonymous synced session');
  String get anonymousHint => _t('Favoritos e biblioteca ficam ligados a este dispositivo.',
      'Favorites and library are tied to this device.');
  String get appearance => _t('Aparência', 'Appearance');
  String get themeSystem => _t('Sistema', 'System');
  String get themeLight => _t('Claro', 'Light');
  String get themeDark => _t('Escuro', 'Dark');
  String get language => _t('Idioma', 'Language');
  String get notifications => _t('Notificações', 'Notifications');
  String get notificationsHint => _t('Avisos de novos ports (simulado)', 'New port alerts (simulated)');
  String get about => _t('Sobre o PORTIX', 'About PORTIX');
  String get settingsSection => _t('Preferências', 'Preferences');
  String get activity => _t('Atividade', 'Activity');
  String get dataSource => _t(
      'Catálogo público de ports (fe2rr) com capas do LaunchBox Games Database. Todos os créditos aos projetos originais.',
      'Public port catalog (fe2rr) with covers from LaunchBox Games Database. All credits to the original projects.');
  String get versionLabel => _t('Versão', 'Version');
  String get dataSection => _t('Dados', 'Data');
  String get reloadCatalog => _t('Recarregar catálogo', 'Reload catalog');
  String get catalogReloaded => _t('Catálogo atualizado', 'Catalog refreshed');
  String get clearCache => _t('Limpar cache local', 'Clear local cache');
  String get cacheCleared => _t('Cache limpo', 'Cache cleared');
  String get madeWith => _t('Feito com Flutter · dados abertos', 'Built with Flutter · open data');

  // ---------------------------------------------------------------- estados
  String get errorGeneric => _t('Algo deu errado.', 'Something went wrong.');
  String get errorNetwork => _t('Sem conexão com o catálogo. Verifique sua internet.',
      'No connection to the catalog. Check your internet.');
  String get errorServer => _t('O catálogo não respondeu como esperado.', 'The catalog did not respond as expected.');
  String get errorAuth => _t('Não foi possível criar sua sessão anônima.', 'Could not create your anonymous session.');
  String get errorNotFound => _t('Jogo não encontrado.', 'Game not found.');
  String get tryAgain => _t('Tentar de novo', 'Try again');
  String get configTitle => _t('Configuração ausente', 'Missing configuration');
  String get configBody => _t('Defina SUPABASE_URL e SUPABASE_ANON_KEY no build via --dart-define.',
      'Set SUPABASE_URL and SUPABASE_ANON_KEY at build time via --dart-define.');
  String get close => _t('Fechar', 'Close');
  String get loading => _t('Carregando', 'Loading');

  // -------------------------------------------------------------- navegação+
  String get navExplore => _t('Explorar', 'Explore');
  String get navNews => _t('Notícias', 'News');
  String get navHub => _t('Meu Hub', 'My Hub');
  String get navMenu => _t('Menu', 'Menu');

  // ------------------------------------------------------------------ home+
  String get homeIntroTitle => _t('Seu próximo jogo começa aqui.',
      'Your next game starts here.');
  String get homeIntroBody => _t(
      'Um catálogo aberto de ports para Android, curado por popularidade e avaliado pela comunidade. Explore, favorite e acompanhe suas instalações.',
      'An open catalog of Android ports, curated by popularity and rated by the community. Explore, favorite and track your installs.');
  String get sectionExploreBy => _t('Explorar por seção', 'Explore by section');
  String get sectionNews => _t('Novidades', 'What\'s new');
  String get sectionTopRated => _t('Mais bem avaliados', 'Top rated');
  String get sectionPopular => _t('Mais populares', 'Most popular');
  String get tileAndroidPorts => _t('Ports Android', 'Android ports');
  String get tileHandheld => _t('Portáteis', 'Handhelds');
  String get tileMobile => _t('Mobile', 'Mobile');

  // --------------------------------------------------------------- explore+
  String get exploreTitle => _t('Explorar', 'Explore');

  // ---------------------------------------------------------------- notícias
  String get newsTitle => _t('Notícias', 'News');
  String get newsSubtitle => _t('Novidades e atualizações do catálogo.',
      'Catalog news and updates.');
  String get newsAdded => _t('Adicionado', 'Added');
  String get newsUpdated => _t('Atualizado', 'Updated');
  String get newsEmpty => _t('Sem novidades por enquanto', 'No news yet');
  String get newsEmptyBody => _t('Assim que o catálogo for atualizado, aparece aqui.',
      'As soon as the catalog is updated, it shows up here.');

  // ------------------------------------------------------------------- hub
  String get hubTitle => _t('Meu Hub', 'My Hub');
  String get hubFavorites => _t('Favoritos', 'Favorites');
  String get hubInstalled => _t('Instalados', 'Installed');
  String get hubDownloads => _t('Downloads', 'Downloads');

  // ------------------------------------------------------------------ menu
  String get menuTitle => _t('Menu', 'Menu');
  String get account => _t('Conta', 'Account');
  String get accentColor => _t('Cor de destaque', 'Accent color');
  String get appearanceSection => _t('Preferências', 'Preferences');

  // -------------------------------------------------------------- detalhes+
  String get installedAction => _t('Marcar como instalado', 'Mark as installed');
  String get uninstalledAction => _t('Marcar como não instalado', 'Mark as not installed');
  String get infoTitle => _t('Informações', 'Information');
  String get descriptionTitle => _t('Descrição', 'Description');
  String get compatTitle => _t('Roda no seu celular?', 'Does it run on your phone?');
  String get compatSubtitle => _t('Relatos da comunidade, aparelho por aparelho.',
      'Community reports, device by device.');
  String get compatWorks => _t('Funciona bem', 'Runs well');
  String get compatPatch => _t('Precisa de patch', 'Needs a patch');
  String get compatBroken => _t('Não roda', 'Does not run');
  String get compatReport => _t('Relatar', 'Report');
  String get compatSent => _t('Relato enviado. Obrigado!', 'Report sent. Thanks!');
  String compatReports(int n) =>
      _t('$n ${n == 1 ? 'relato' : 'relatos'}', '$n ${n == 1 ? 'report' : 'reports'}');
  String get downloadsLabel => _t('baixados', 'downloads');
  String get sourceOnly => _t(
      'Este port não tem um APK direto. Abrindo a fonte para você baixar.',
      'This port has no direct APK. Opening the source so you can download it.');
  String get notApk => _t('O link não apontou para um APK válido.',
      'The link did not point to a valid APK.');

  // --------------------------------------------------------- contas / perfil
  String get authTitle => _t('Entrar no PORTIX', 'Sign in to PORTIX');
  String get authSubtitle => _t('Crie uma conta para avaliar jogos e montar seu perfil.',
      'Create an account to rate games and build your profile.');
  String get signIn => _t('Entrar', 'Sign in');
  String get signUp => _t('Criar conta', 'Create account');
  String get signOut => _t('Sair', 'Sign out');
  String get email => _t('E-mail', 'Email');
  String get password => _t('Senha', 'Password');
  String get yourName => _t('Seu nome', 'Your name');
  String get continueWithGoogle => _t('Continuar com Google', 'Continue with Google');
  String get loginRequired => _t('Entre para avaliar.', 'Sign in to rate.');
  String get editProfile => _t('Editar perfil', 'Edit profile');
  String get coverUrlLabel => _t('URL da capa (opcional)', 'Cover URL (optional)');
  String get coverHint => _t('https://...', 'https://...');
  String get saveChanges => _t('Salvar', 'Save');
  String get profileSaved => _t('Perfil atualizado', 'Profile updated');
  String get guestLabel => _t('Convidado', 'Guest');
  String get accountSection => _t('Conta', 'Account');
  String get passwordShort => _t('A senha precisa de 6+ caracteres', 'Password needs 6+ characters');
  String get emailRequired => _t('Informe um e-mail válido', 'Enter a valid email');
  String get authCheckEmail => _t('Confira seu e-mail para confirmar a conta.',
      'Check your email to confirm the account.');
  String get googleUnavailable => _t('Login com Google ainda não está configurado neste projeto.',
      'Google sign-in is not configured in this project yet.');

  // ------------------------------------------------------------ compat v2
  String get compatPerfect => _t('Roda perfeito', 'Runs perfectly');
  String get compatGood => _t('Roda bem', 'Runs well');
  String get compatStutter => _t('Com travadas', 'Stutters');
  String get compatUnplayable => _t('Injogável', 'Unplayable');
  String get compatNotRun => _t('Não roda', 'Does not run');
  String get compatCommunity => _t('Como roda por aparelho', 'How it runs by device');
  String get compatNoReports => _t('Ainda sem relatos da comunidade.', 'No community reports yet.');
  String get compatYourDevice => _t('Seu aparelho', 'Your device');
  String get compatSameSoc => _t('Mesmo processador', 'Same chipset');
  String get chooseApk => _t('Escolha o APK', 'Choose the APK');
  String get searchingRelease => _t('Buscando a release…', 'Looking up the release…');

  // -------------------------------------------------------------- contagens
  String gameCount(int n) => _t('$n ${n == 1 ? 'jogo' : 'jogos'}', '$n ${n == 1 ? 'game' : 'games'}');
  String portCount(int n) => _t('$n ${n == 1 ? 'port' : 'ports'}', '$n ${n == 1 ? 'port' : 'ports'}');
  String platformCount(int n) => _t('$n ${n == 1 ? 'plataforma' : 'plataformas'}',
      '$n ${n == 1 ? 'platform' : 'platforms'}');
  String resultsCount(int n) => _t('$n ${n == 1 ? 'resultado' : 'resultados'}',
      '$n ${n == 1 ? 'result' : 'results'}');
  String reviewCount(int n) => _t('$n ${n == 1 ? 'avaliação' : 'avaliações'}',
      '$n ${n == 1 ? 'review' : 'reviews'}');
  String progressPercent(int value) => '$value%';
}

extension L10nContext on BuildContext {
  L10n get l10n => L10n(Localizations.localeOf(this));
}
