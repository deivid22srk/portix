-- ============================================================================
-- PORTIX — 0007: integridade do canal breach_signal
--
-- Endurecimento: um cliente só pode registrar um sinal em nome próprio
-- (reporter nulo = anônimo sem sessão). Impede "framing" de outro usuário.
-- Idempotente.
-- ============================================================================

drop policy if exists breach_signal_insert on public.breach_signal;
create policy breach_signal_insert on public.breach_signal
  for insert to anon, authenticated
  with check (reporter is null or reporter = auth.uid());
