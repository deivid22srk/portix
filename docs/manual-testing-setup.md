# Roteiro de testes manuais — Setup + Instalador (Android real)

> Escopo: primeira configuração (`/setup`), rechec de permissões, instalador
> Android (PackageInstaller + pré-aprovação Android 14+), instalador Shizuku,
> integridade de APK e limpeza de sessões órfãs.
>
> Comportamento de referência: `lib/features/install/*`,
> `lib/features/setup/*` e os canais descritos no
> `scripts/criador_iter1_log.md` (decisões D1-D42). Os testes automatizados
> cobrem reducer/controller/planejamento; **este roteiro cobre o que só
> existe no aparelho**: diálogos do sistema, Shizuku real, armazenamento e
> morte de processo.

---

## 0. Preparação

### 0.1 Aparelhos sugeridos

| Papel | Versão do Android | O que valida |
|---|---|---|
| Principal | Android 14+ (SDK 34+) | pré-aprovação ANTES do download |
| Secundário | Android 11-13 | diálogo único no commit (sem pré-aprovação) |
| Opcional | Android ≤ 10 | instalação via intent/sessão clássica |

### 0.2 Instalar o PORTIX

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Pacote do app: `com.deivid22srk.portix`.

Reset completo entre cenários (apaga prefs do setup, cache de pacotes e
APKs privados):

```bash
adb shell pm clear com.deivid22srk.portix
```

### 0.3 Instalar e iniciar o Shizuku

1. Instale o app Shizuku (Play Store ou
   `https://github.com/RikkaApps/Shizuku/releases`).
2. **Android 11+ (Wireless debugging):** abra o Shizuku → "Iniciar via
   Wireless debugging" → parear/permitir conforme o app guiar.
3. **Android 10 ou anterior / alternativa por cabo:**

   ```bash
   adb shell sh /sdcard/Android/data/moe.shizuku.privileged.api/start.sh
   ```

4. A permissão do PORTIX no Shizuku é pedida na primeira instalação com o
   Shizuku ativo (diálogo do próprio Shizuku) ou pelo botão "Permitir com
   Shizuku" no setup/painel.

### 0.4 Captura de evidência

Limpe o log antes de cada cenário e filtre o que interessa:

```bash
adb logcat -c
adb logcat | grep -E "PackageInstaller|portix|Shizuku|ActivityTaskManager"
```

Sessões do PackageInstaller (evidência de sessão ativa/órfã):

```bash
adb shell dumpsys package installs
```

Arquivos privados de APK (emulador/build debug; em aparelhos com storage
restrito use `run-as` em build debug):

```bash
adb shell ls /storage/emulated/0/Android/data/com.deivid22srk.portix/files/apk/
```

---

## 1. Setup: primeira abertura, retomada e "não reaparece"

**Cenário 1a — primeira abertura**

1. `adb shell pm clear com.deivid22srk.portix` e abra o app.
2. **Esperado:** `/setup` abre direto, **sem flash** de outra tela (o
   redirect decide antes de construir páginas).
3. Etapas na ordem: Boas-vindas → Instalar apps desconhecidos →
   Notificações (só Android 13+) → Shizuku (só se instalado) → Instalador
   preferido → Pronto.
4. Faça 2 etapas e **mate o processo** no meio:

   ```bash
   adb shell am force-stop com.deivid22srk.portix
   ```

5. Reabra o app. **Esperado:** retoma da etapa onde parou (`setup.doneSteps`
   persistido por etapa).

**Cenário 1b — não reaparece**

1. Conclua o setup ("Começar"/"Continuar" até "Pronto").
2. **Esperado:** vai para `/home`; fechar e reabrir o app **nunca** mostra o
   setup de novo (`setup.version=1` gravado).
3. Em Configurações → Instalação → "Rever configuração inicial": modo
   revisão abre com botão **"Fechar"**, navega livre e **não grava nada**
   (não reinicia o setup, não reescreve `setup.version`).

**Cenário 1c — "Agora não"**

1. Setup pendente → toque em **"Agora não"** em qualquer etapa.
2. **Esperado:** vai para `/home` e **reabrir o app não traz o setup de
   volta** (a versão é gravada mesmo saindo sem concluir).

---

## 2. Rechec de permissão "Instalar apps desconhecidos"

1. Com o setup pendente, na etapa "Instalar apps desconhecidos", toque em
   **"Permitir instalar apps"** (abre a tela do sistema já direcionada ao
   PORTIX).
2. **Negue** e volte ao app. **Esperado:** etapa continua pendente, mensagem
   de não concedida; o app NÃO trava — dá para seguir com "Continuar"
   quando concedida ou pular a etapa.
3. Toque de novo, **conceda** e volte. **Esperado:** a etapa avança
   sozinha (rechec ao voltar — `permissionsProvider.refresh()` no
   `onResume`), sem precisar tocar de novo.
4. Também vale para Notificações (Android 13+): negar → voltar → conceder →
   etapa avança sozinha.

**No fluxo de instalação** (tela de detalhes): toque em "Baixar" sem a
permissão → sheet pede permissão → negar e voltar → **falha clara
(`permission-required`)** e o próximo toque reabre o sheet; conceder e
voltar → o download começa normalmente.

---

## 3. Android 14+ (SDK 34+): UM único diálogo ANTES do download

Pré-condições: Android 14+, permissão "Instalar apps desconhecidos"
concedida, **pacote já conhecido** (instale o port uma vez — o cache
`install.packages` guarda o pacote lido do APK — ou use uma tarefa que já
traz `packageName`).

1. Toque em **"Baixar"**.
2. **Esperado:** o diálogo de pré-aprovação do sistema aparece **ANTES de
   qualquer byte baixado** (fase `awaitingPreapproval`; gaveta de
   notificações ainda sem download).
3. **Aprove** → o download começa (progresso na notificação) e ao terminar a
   instalação roda **sem NENHUM novo diálogo** (sessão `commitPrepared`).
   CTA termina em "Abrir o app".
4. Repita com **"Recusar"**: o fluxo volta a parado **e nada é baixado**
   (nenhuma notificação de download, nenhum arquivo novo em
   `…/files/apk/`).

**Evidência (3):**

```bash
adb logcat -c && adb logcat | grep -E PackageInstaller
```

Esperado — uma única sessão com `requestUserPreapproval` ANTES do início do
download e, depois do commit, `STATUS_PENDING_USER_ACTION` apenas para a
pré-aprovação (nenhum segundo diálogo pós-download). Uma recusa não deve
gerar chamada de download no motor.

```bash
# conferir que nada foi baixado após a recusa:
adb shell ls /storage/emulated/0/Android/data/com.deivid22srk.portix/files/apk/
```

---

## 4. Android ≤ 13: diálogo único no commit

Pré-condições: aparelho Android 13- (sem pré-aprovação) e permissão
concedida.

1. Toque em "Baixar" → download roda direto (sem diálogo antes).
2. Ao terminar, a sessão é gravada e o **commit** abre o diálogo do
   instalador do Android (`commitFresh`, `MODE_FULL_INSTALL`) — **exatamente
   um diálogo**, no fim.
3. Aprove → "Abrir o app". O APK privado é apagado após a confirmação.
4. Repita e recuse no diálogo → falha clara no CTA, APK descartado, nenhum
   app parcialmente instalado.

**Evidência:** `adb logcat | grep -E PackageInstaller` mostra a sessão
criada só no fim (staging após o download completo) e
`STATUS_PENDING_USER_ACTION` no commit.

---

## 5. Shizuku ATIVO: instalação sem diálogo e morte no meio

**Cenário 5a — silenciosa**

1. Shizuku iniciado (§0.3) e permissão concedida ao PORTIX (estado "Ativo"
   no painel/etapa de Shizuku).
2. Preferência "Shizuku" em Instalador preferido (ou "Automático" — com o
   Shizuku ativo o automático escolhe Shizuku).
3. Baixe um port. **Esperado:** do fim do download até "Abrir o app"
   **nenhum diálogo do sistema** (instalação via binder, sessão do shell).
4. Confirme no logcat que o caminho foi o Shizuku (sessão criada com o
   binder do shell) e que o download/downgrade passou
   (`INSTALL_ALLOW_DOWNGRADE`).

**Cenário 5b — Shizuku morre no meio**

1. Com o download em andamento (ou logo após concluir, antes de tocar no
   diálogo de confirmação de instalação), **mate o servidor do Shizuku**:
   abra o app Shizuku → Parar servidor, ou:

   ```bash
   adb shell killall shizuku_server 2>/dev/null || \
     adb shell am force-stop moe.shizuku.privileged.api
   ```

2. **Esperado:** falha **clara e rápida** no CTA (`shizuku-unavailable`),
   com a oferta **"Usar o instalador do Android desta vez"**.
3. Toque na oferta → o plano é re-resolvido com o instalador do Android
   mantendo o pacote/pré-aprovação → a instalação completa pelo caminho
   normal (1 diálogo, no Android ≤ 13, ou nada no 14+ já pré-aprovado).
4. Rechec de sanidade: o estado do Shizuku no painel volta a
   "instalado/parado" e o app não crasha em nenhum momento.

**Cenário 5c — permissão do Shizuku revogada**

1. Shizuku → PORTIX → revogue a permissão (ou inicie o servidor de novo sem
   conceder).
2. Instale pelo Shizuku. **Esperado:** o plano entra em **bloqueado** com o
   motivo "Falta permissão" e a mesma oferta de fallback do Android.

---

## 6. Integridade: cancelamento, APK truncado e downgrade

**Cenário 6a — cancelar download**

1. Baixe um port grande e cancele pelo tile de downloads no meio.
2. **Esperado:** CTA volta a "Baixar", nenhum APK é instalado, o `.part`
   some no próximo startup (ou é mantido para retomada — não deve haver
   lixo instalado). Se havia sessão pré-aprovada, ela é **abandonada**
   (ver `dumpsys package installs` sem sessões penduradas do PORTIX).

**Cenário 6b — APK truncado é descartado** (build debug; sem `run-as` em
release a checagem vale pelos digests reais do GitHub)

1. Complete um download com asset que tenha digest publicado no GitHub.
2. **Antes de instalar**, trunque o APK:

   ```bash
   adb shell run-as com.deivid22srk.portix \
     ls files/apk/   # anote o nome do portix-*.apk
   adb shell run-as com.deivid22srk.portix \
     truncate -s 1000 files/apk/portix-<id>.apk
   ```

3. Toque em instalar (reinstalação do APK existente). **Esperado:** verificação
   de integridade **fail-closed** — fase `failed` com erro de integridade
   (digest divergente) e **o arquivo truncado é APAGADO** (nada é enviado ao
   instalador).

**Cenário 6c — downgrade**

1. Instale a versão mais recente de um port (ex.: v0.1.4).
2. Selecione uma **versão mais antiga** (v0.1.3) e confirme o diálogo
   "Baixar assim mesmo".
   - **Instalador do Android:** esperado **bloqueio** (`downgradeBlocked`) —
     falha clara, APK descartado, versão instalada permanece a 0.1.4.
   - **Shizuku:** esperado **permitir** (flag `INSTALL_ALLOW_DOWNGRADE`) —
     desde que as assinaturas batam, a versão anterior instala de fato.

---

## 7. Espaço em disco e morte do app com sessão aberta

**Cenário 7a — pouco espaço**

1. Encha o armazenamento até sobrar menos que ~2× o tamanho do APK + 64 MB:

   ```bash
   adb shell dd if=/dev/zero of=/sdcard/lixo.bin bs=1m count=8000
   ```

2. Toque em "Baixar". **Esperado:** falha **antes de baixar qualquer coisa**
   (`low-storage`) — a checagem de `freeBytes` ocorre antes do resolvedor.
3. Apague o lixo (`adb shell rm /sdcard/lixo.bin`) e confirme que o download
   então funciona.

**Cenário 7b — morte do app com sessão aberta**

1. Com Android 14+ e pacote conhecido: toque em "Baixar" e **aguarde o
   diálogo de pré-aprovação** (sessão já criada).
2. Morte do processo com o diálogo aberto:

   ```bash
   adb shell am force-stop com.deivid22srk.portix
   ```

3. Confirme a sessão órfã:

   ```bash
   adb shell dumpsys package installs | grep -A5 "Sessions"
   ```

4. Reabra o PORTIX. **Esperado:** no startup o app roda
   `cleanupOrphanSessions()` — a sessão órfã é **abandonada** (o `dumpsys`
   deixa de listá-la) e nenhum diálogo fantasma reaparece; o fluxo do jogo
   está em repouso (CTA "Baixar" normal).

---

## Tabela de permissões esperadas no logcat

Sequência esperada de chamadas por cenário (canais `portix/*` + sistema).
Filtre com `adb logcat | grep -E "portix|PackageInstaller|Shizuku"`.

| Fase | Canal → método | Resultado esperado | Observações |
|---|---|---|---|
| Startup | `portix/install` → `cleanupOrphanSessions` | void | abandona sessões órfãs |
| Startup / painel | `portix/permissions` → `snapshot` | `{canInstallApps, notificationsGranted, shizuku, sdkInt, freeBytes, isAndroid:true}` | rechec a cada `onResume` |
| Painel/CTA | `portix/shizuku` → `status` | `notInstalled\|installedStopped\|runningNoPermission\|active` | também publicado em `portix/shizuku/events` |
| Pré-download | `portix/install` → `freeBytes` | int (−1 = desconhecido) | guarda `low-storage` |
| Pré-aprovação (14+) | `portix/install` → `prepare(key, attemptId, packageName, label, iconPng, sizeBytes)` | `true` | eventos: `prepared` → `preapprovalApproved\|Declined\|Failed` |
| Download | `portix/downloader` (motor Rust) | progresso na notificação | fase `downloading` |
| Pós-download | `portix/install` → `sha256(path)` | hex minúsculo ou null (fail-closed) | só quando o asset tem digest |
| Pós-download | `portix/apk` → `inspect(path)` / `installed(packageName)` | `{packageName, versionName?, versionCode?}` / null | valida pacote + downgrade |
| Instalação pré-aprovada | `portix/install` → `commitPrepared(key, sessionId, path, expectedPackage)` | void | eventos `writing`/`committing` → `installDone\|installFailed` |
| Instalação clássica | `portix/install` → `commitFresh(key, path)` | void | 1 diálogo do sistema no commit |
| Cancelamento | `portix/install` → `abandon(sessionId)` | void | também na morte de tarefa |
| Cancelar prepare | `portix/install` → `cancelPrepare(key, attemptId)` | void | impedir diálogo tardio |
| Instalação Shizuku | `portix/shizuku` → `install(key, path, expectedPackage)` | `{ok, sessionId?}` | eventos via `portix/install/events` (mesmo formato) |

**Eventos do sistema (PackageInstaller)** — os payloads esperados:

- Pré-aprovação: sessão criada + `requestUserPreapproval` (SÓ Android 14+)
  antes do download; recusa → `STATUS_FAILURE_ABORTED` para a sessão.
- Commit (com/sem pré-aprovação): `STATUS_PENDING_USER_ACTION` (diálogo único)
  → `STATUS_SUCCESS`; falhas com `STATUS_FAILURE_*` + `EXTRA_STATUS_MESSAGE`
  legível no CTA.
- Shizuku: nenhuma linha de diálogo do PackageInstaller do app; sessão criada
  pelo binder do shell (`installFlags` com `INSTALL_ALLOW_DOWNGRADE`).

---

## Checklist rápido (assinar ao terminar)

- [ ] 1a/1b/1c — setup abre, retoma, não reaparece, "Agora não" ok
- [ ] 2 — rechec concedido avança sozinho; negado não trava
- [ ] 3 — Android 14+: 1 diálogo antes do download; recusa não baixa (logcat anexado)
- [ ] 4 — Android ≤13: 1 diálogo só no commit
- [ ] 5 — Shizuku silencioso; morte no meio → falha clara + fallback Android; permissão revogada → bloqueado
- [ ] 6 — cancelamento limpo; APK truncado descartado e apagado; downgrade bloqueado (Android) / permitido (Shizuku)
- [ ] 7 — `low-storage` antes de baixar; sessão órfã abandonada no relaunch
