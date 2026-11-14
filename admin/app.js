/* PORTIX · Painel ADM — app estático (sem build).
 * Fala direto com o Supabase (Auth + RPCs protegidos por papel). */

const CFG_KEY = 'portix_admin_cfg';
const SESSION_KEY = 'portix_admin_session';

const $ = (id) => document.getElementById(id);

const state = {
  cfg: loadJson(CFG_KEY),
  session: loadJson(SESSION_KEY),
  role: null,
  permissions: {},
};

function loadJson(key) {
  try {
    return JSON.parse(localStorage.getItem(key) || 'null');
  } catch {
    return null;
  }
}

function saveJson(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

function show(view) {
  ['view-config', 'view-login', 'view-denied', 'view-dash', 'view-admins'].forEach((id) => {
    $(id).classList.toggle('hidden', id !== view);
  });
  const authed = ['view-dash', 'view-admins'].includes(view);
  $('tabs').classList.toggle('hidden', !authed);
  $('logout').classList.toggle('hidden', !authed && view !== 'view-denied');
}

function hint(message, isError = false) {
  const el = $('hint');
  el.textContent = message || '';
  el.classList.toggle('hidden', !message);
  el.style.color = isError ? 'var(--danger)' : 'var(--faint)';
}

async function api(path, { method = 'GET', body, auth = true } = {}) {
  const headers = { apikey: state.cfg.key, 'Content-Type': 'application/json' };
  if (auth && state.session?.access_token) {
    headers.Authorization = `Bearer ${state.session.access_token}`;
  }
  const response = await fetch(`${state.cfg.url}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  if (!response.ok) {
    const message = (data && (data.msg || data.message || data.error_description)) || response.status;
    const error = new Error(message);
    error.status = response.status;
    throw error;
  }
  return data;
}

const rpc = (name, params = {}) =>
  api(`/rest/v1/rpc/${name}`, { method: 'POST', body: params });

// ------------------------------------------------------------------ login
async function login() {
  const email = $('login-email').value.trim();
  const password = $('login-pass').value;
  $('login-error').classList.add('hidden');
  const button = $('login-go');
  button.disabled = true;
  try {
    const data = await api('/auth/v1/token?grant_type=password', {
      method: 'POST',
      body: { email, password },
      auth: false,
    });
    state.session = {
      access_token: data.access_token,
      refresh_token: data.refresh_token,
      email: data.user?.email || email,
    };
    saveJson(SESSION_KEY, state.session);
    await enter();
  } catch (error) {
    $('login-error').textContent = `Falha ao entrar: ${error.message}`;
    $('login-error').classList.remove('hidden');
  } finally {
    button.disabled = false;
  }
}

async function enter() {
  try {
    await rpc('admin_bootstrap');
  } catch {
    /* bootstrap é opcional (só promove o root) */
  }
  try {
    state.role = await rpc('admin_me');
  } catch {
    state.role = null;
  }
  if (!state.role) {
    show('view-denied');
    $('who').textContent = state.session?.email || '';
    return;
  }
  $('who').textContent = `${state.session.email} · ${state.role.level}`;
  show('view-dash');
  await Promise.all([loadStats(), loadAdmins()]);
}

function logout() {
  state.session = null;
  state.role = null;
  localStorage.removeItem(SESSION_KEY);
  show('view-login');
  $('who').textContent = '';
  $('login-pass').value = '';
}

// ------------------------------------------------------------- estatísticas
async function loadStats() {
  try {
    const stats = await rpc('admin_stats');
    const items = [
      ['Jogos', stats.games],
      ['Ports', stats.ports],
      ['Plataformas', stats.platforms],
      ['Usuários', stats.users],
      ['ADMs', stats.admins],
      ['Avaliações', stats.reviews],
      ['Favoritos', stats.favorites],
      ['Biblioteca', stats.library],
      ['Downloads', stats.downloads],
    ];
    $('stats').innerHTML = '';
    for (const [label, value] of items) {
      const div = document.createElement('div');
      div.className = 'stat';
      const v = document.createElement('div');
      v.className = 'value';
      v.textContent = String(value ?? 0);
      const l = document.createElement('div');
      l.className = 'label';
      l.textContent = label;
      div.append(v, l);
      $('stats').append(div);
    }
    renderRecent(stats.recent_reviews || []);
  } catch (error) {
    hint(`Erro ao carregar estatísticas: ${error.message}`, true);
  }
}

function renderRecent(rows) {
  const tbody = $('recent').querySelector('tbody');
  tbody.innerHTML = '';
  for (const row of rows) {
    const tr = document.createElement('tr');
    tr.append(
      cell(row.game),
      cellWithAdmin(row.author, row.author_role),
      cell(row.rating ? `${row.rating}★` : '—'),
      cell(row.verdict || '—'),
      cell(row.fps != null ? `${row.fps} FPS` : '—'),
      cell(formatDate(row.created_at)),
    );
    tbody.append(tr);
  }
}

function cell(text) {
  const td = document.createElement('td');
  td.textContent = text ?? '—';
  return td;
}

function cellWithAdmin(author, role) {
  const td = document.createElement('td');
  td.textContent = author ?? '—';
  if (role) {
    const badge = document.createElement('span');
    badge.className = 'badge';
    badge.style.marginLeft = '8px';
    badge.textContent = role === 'root' ? 'root' : 'ADM';
    td.append(badge);
  }
  return td;
}

function formatDate(value) {
  if (!value) return '—';
  const date = new Date(value);
  return date.toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
}

// ----------------------------------------------------------- administradores
async function loadAdmins() {
  $('role-badge').textContent = state.role?.level || '—';
  const isRoot = state.role?.level === 'root';
  $('admins-root').classList.toggle('hidden', !isRoot);
  const tbody = $('admins').querySelector('tbody');
  tbody.innerHTML = '';
  try {
    const rows = await rpc('admin_list');
    for (const row of rows) {
      tbody.append(adminRow(row, isRoot));
    }
  } catch (error) {
    hint(`Só o ADM raiz vê a lista completa (${error.message}).`);
  }
}

function adminRow(row, isRoot) {
  const tr = document.createElement('tr');

  const email = document.createElement('td');
  email.textContent = row.email ?? row.user_id;

  const level = document.createElement('td');
  const chip = document.createElement('span');
  chip.className = `role-chip role-${row.level}`;
  chip.textContent = row.level;
  level.append(chip);

  const perms = document.createElement('td');
  const keys = Object.entries(row.permissions || {})
    .filter(([, value]) => value)
    .map(([key]) => key);
  perms.textContent = row.level === 'root' ? 'todas' : keys.join(', ') || '—';

  const actions = document.createElement('td');
  if (isRoot && row.level !== 'root') {
    const button = document.createElement('button');
    button.className = 'revoke';
    button.textContent = 'Revogar';
    button.onclick = async () => {
      try {
        await rpc('admin_revoke', { p_user: row.user_id });
        await loadAdmins();
      } catch (error) {
        hint(`Falha ao revogar: ${error.message}`, true);
      }
    };
    actions.append(button);
  }

  tr.append(email, level, perms, actions);
  return tr;
}

async function grant() {
  const email = $('grant-email').value.trim();
  const level = $('grant-level').value;
  const permissions = {};
  document.querySelectorAll('[data-perm]').forEach((input) => {
    permissions[input.dataset.perm] = input.checked;
  });
  try {
    await rpc('admin_grant', {
      p_email: email,
      p_level: level,
      p_permissions: permissions,
    });
    $('grant-email').value = '';
    hint(`Acesso concedido a ${email}.`);
    await loadAdmins();
  } catch (error) {
    hint(`Falha ao conceder: ${error.message}`, true);
  }
}

// ------------------------------------------------------------------- wire
function wire() {
  $('cfg-save').onclick = () => {
    const url = $('cfg-url').value.trim().replace(/\/$/, '');
    const key = $('cfg-key').value.trim();
    if (!url || !key) return;
    state.cfg = { url, key };
    saveJson(CFG_KEY, state.cfg);
    show('view-login');
  };
  $('cfg-reset').onclick = () => {
    localStorage.removeItem(CFG_KEY);
    localStorage.removeItem(SESSION_KEY);
    state.cfg = null;
    state.session = null;
    boot();
  };
  $('login-go').onclick = login;
  $('login-pass').addEventListener('keydown', (event) => {
    if (event.key === 'Enter') login();
  });
  $('logout').onclick = logout;
  $('refresh').onclick = loadStats;
  $('grant-go').onclick = grant;
  document.querySelectorAll('.tab').forEach((tab) => {
    tab.onclick = () => {
      document.querySelectorAll('.tab').forEach((t) => t.classList.remove('active'));
      tab.classList.add('active');
      show(tab.dataset.view === 'dash' ? 'view-dash' : 'view-admins');
    };
  });
}

function boot() {
  wire();
  if (!state.cfg) {
    show('view-config');
    return;
  }
  if (state.session?.access_token) {
    enter();
  } else {
    show('view-login');
  }
}

boot();
