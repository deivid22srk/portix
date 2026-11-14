-- ============================================================================
-- PORTIX — 0006: corrige leitura cruzada em compat_reports (sinal do Atacante)
--
-- Vetor: a policy permissiva `compat_public_read` (USING true) valia também
-- para o role `authenticated`. Como toda sessão anônima do app é
-- `authenticated`, bastava um GET em /rest/v1/compat_reports para ler
-- user_id/status/note de TODOS os usuários.
--
-- Causa raiz: policy de SELECT pública somada (OR) à policy do dono. Revogar o
-- privilégio do `anon` não bastava. Correção: remover a policy pública; a
-- leitura passa a ser só do dono e o agregado público continua vindo de
-- `compat_summary` (SECURITY DEFINER). Idempotente.
-- ============================================================================

drop policy if exists compat_public_read on public.compat_reports;

-- Reafirma a policy do dono (leitura/escrita apenas das próprias linhas).
drop policy if exists compat_write_own on public.compat_reports;
create policy compat_write_own on public.compat_reports
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Reforça: nenhum privilégio de leitura direta para anon.
revoke select on public.compat_reports from anon;
