# SiftBar — Plano de Implementação

> App de barra de menu para macOS que **analisa** o sistema, apresenta uma **lista explicada** de problemas/oportunidades e permite **aplicar apenas o que você escolher** — com preview e classificação de risco.

- **Nome:** SiftBar (verificado em 04/11/2026: sem app/produto homônimo; `.app` livre; GitHub sem projeto relevante)
- **Pasta do projeto:** `~/Documents/SiftBar`
- **Bundle ID provisório:** `com.andredias.siftbar`
- **Alvo mínimo:** macOS 13.0+ (Apple Silicon; Intel não é prioridade)
- **Idioma:** código, comentários, README e UI em inglês
- **Status:** Fases 0 e 1 concluídas — aguardando aprovação da Fase 2

---

## 1. Objetivo

Reproduzir com segurança o trabalho manual feito na sessão de limpeza, em um fluxo de 3 passos:

1. **Analisar** — varredura somente leitura (memória, swap, processos, itens de inicialização, serviços, disco, caches, sobras).
2. **Revisar** — cada item aparece com título, detalhe, impacto (MB/GB ou RAM), **origem do dado** e selo de risco: `Seguro` / `Atenção` / `Perigoso`.
3. **Aplicar** — você marca o que quer; o app mostra o **comando exato** e só executa após confirmação. Nada é automático por padrão.

### Princípios

- **Read-only por padrão.** O botão "Analisar" nunca altera nada.
- **Nada de "limpar tudo".** Toda ação é item a item e reversível quando possível.
- **Transparência total.** Cada linha mostra de onde veio a informação e o que será executado.
- **Sem placebo.** O foco é causa (agentes, login items, apps pesados), não "esvaziar RAM".
- **Nunca tocar em área protegida por SIP** (`/System`, `AssetsV2`, etc.).

### Fora de escopo (v1)

- Remover/limpar AssetsV2 e qualquer caminho protegido por SIP.
- "Otimizar RAM" com `purge` (cosmético).
- Matar processos automaticamente ou em massa.
- App Store / sandbox (incompatível com o propósito).
- Suporte a Intel e macOS < 13.

---

## 2. Ambiente verificado

| Item | Resultado |
|---|---|
| macOS | 27.2 (build 26B123) |
| Xcode completo | ❌ ausente |
| Command Line Tools | ✅ `/Library/Developer/CommandLineTools` |
| Swift | 6.4.2 (arm64) |
| SDK | MacOSX 27.2 |
| `MenuBarExtra` (SwiftUI) | ✅ compila via `swiftc` (validado) |
| Ferramentas | `codesign`, `plutil`, `iconutil`, `sqlite3` disponíveis |

**Consequência:** build com **`swiftc` direto + script de empacotamento**, sem Xcode. O SwiftPM desta instalação de CLT está quebrado (falha de link do `PackageDescription`), então o script compila as fontes diretamente; o `Package.swift` fica mantido para toolchains saudáveis. Assinatura **ad-hoc** (`codesign -s -`) para uso local. Se um dia for distribuir, entra Developer ID + notarização.

---

## 3. Arquitetura

```
SiftBar/
├── PLAN.md
├── Package.swift
├── Sources/SiftBar/
│   ├── App/
│   │   ├── SiftBarApp.swift        # @main + MenuBarExtra + AppDelegate
│   │   └── AppState.swift           # estado observável (scan, seleção, execução)
│   ├── Core/
│   │   ├── Models.swift             # ScanItem, Risk, Action, ScanReport
│   │   ├── Analyzer.swift           # regras e heurísticas de risco
│   │   ├── Executor.swift           # dry-run, preview e apply
│   │   ├── CommandRunner.swift      # execução segura (sem shell, com timeout)
│   │   └── HistoryStore.swift       # log/histórico em JSON
│   ├── Collectors/
│   │   ├── MemoryCollector.swift
│   │   ├── ProcessCollector.swift
│   │   ├── StartupCollector.swift   # login items, launch agents/daemons
│   │   ├── BrewCollector.swift
│   │   ├── DiskCollector.swift
│   │   ├── CacheCollector.swift
│   │   └── OrphanCollector.swift
│   ├── UI/
│   │   ├── DashboardView.swift      # resumo + botão Analisar
│   │   ├── ReviewView.swift         # lista com checkboxes e filtros
│   │   ├── ItemRow.swift
│   │   ├── RiskBadge.swift
│   │   ├── PreviewSheet.swift       # comandos exatos antes de aplicar
│   │   └── HistoryView.swift
│   └── Support/
│       ├── Formatters.swift
│       └── Logger.swift
├── Resources/
│   ├── Info.plist                   # LSUIElement = true
│   └── AppIcon.icns                 # opcional, fase final
└── scripts/
    ├── build.sh                     # swift build + monta .app + assina ad-hoc
    ├── run.sh                       # build + open
    └── clean.sh
```

### Decisões técnicas

| Decisão | Escolha | Motivo |
|---|---|---|
| UI | SwiftUI (`MenuBarExtra`, macOS 13+) | Nativo, sem Xcode, leve |
| Janela | `NSWindow` + `NSHostingView` aberta pelo menu | Evita janela automática no launch; melhor para lista longa que popover |
| Concorrência | `async/await` + `TaskGroup` | Coletores em paralelo, UI responsiva |
| Execução de comandos | `/usr/bin/env` + array de argumentos | Evita injeção de shell |
| Timeout | 10 s por coletor / 30 s por ação | Não travar o app |
| Persistência | JSON em `~/Library/Application Support/SiftBar/history.json` | Simples, auditável |
| Log | `~/Library/Logs/SiftBar/` | Padrão macOS |
| Distribuição | `.app` local assinado ad-hoc | Sem conta de dev |

---

## 4. Modelo de dados

```swift
enum Risk: String, Codable { case safe, caution, dangerous }

enum Category: String, Codable {
    case memory, processes, startup, services, disk, caches, leftovers
}

enum Action: Codable {
    case none                                   // só informativo
    case killProcess(pid: Int32, name: String)
    case removeLoginItem(name: String)
    case bootout(label: String)                 // launchctl bootout
    case disableLaunchItem(label: String)
    case brewStop(service: String)
    case deletePath(path: String, bytes: Int64)
    case uninstallApp(path: String)
}

struct ScanItem: Identifiable, Codable {
    let id: UUID
    let category: Category
    let title: String
    let detail: String
    let impactLabel: String        // "1,7 GB", "39 processos", "4,1 GB swap"
    let impactBytes: Int64?        // para ordenar
    let risk: Risk
    let action: Action
    let evidence: String           // comando/fonte que gerou o item
}
```

---

## 5. Coletores (Fase 1)

| Coletor | Fonte | Saída |
|---|---|---|
| Memória | `vm_stat`, `sysctl vm.swapusage`, `memory_pressure` | pressão, swap usado, páginas |
| Processos | `ps -Ao pid,user,rss,%mem,comm`, `top -l 1 -o mem` | top N por RAM, dono, nº de processos por app |
| Inicialização | `launchctl list`, `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `osascript` (login items) | itens ativos, falhando, órfãos |
| Serviços | `brew services list` | rodando/parados, estado |
| Disco | `df -k`, `du -sk` em alvos conhecidos | livre/usado, maiores pastas |
| Caches | alvos com whitelist (npm, Expo, Xcode, Docker, Homebrew, Gradle, etc.) | tamanho por cache |
| Sobras | apps instalados vs. `~/Library/Application Support`, `Caches`, `LaunchAgents` | pastas de apps não instalados |

**Regras de robustez:** cada coletor roda isolado; falha de um não derruba o scan; permissões negadas viram item informativo ("sem acesso — conceda Acesso Total ao Disco").

---

## 6. Análise e risco (Fase 2)

| Situação | Risco | Ação sugerida |
|---|---|---|
| Cache recriável (npm, Expo, Gradle) | Seguro | apagar |
| Login item de app desinstalado | Seguro | remover |
| Launch agent que falha repetidamente | Seguro | desabilitar |
| Serviço de dev parado que sobe no boot | Atenção | tirar do boot |
| App pesado aberto (ex.: Chrome 1,7 GB) | Atenção | encerrar (aviso) |
| Agente de app removível mas com função (ex.: antivírus) | Atenção | decidir |
| Processo do sistema / PID crítico | Perigoso | nunca |
| Caminho protegido por SIP | Perigoso | nunca (bloqueado) |
| Arquivo em `~/Documents` | Perigoso | não sugerir apagar |

Cada item recebe também um **score de impacto** para ordenar: bytes liberados > RAM > nº de processos.

---

## 7. Execução segura (Fases 3–5)

1. Usuário marca itens → botão **"Revisar selecionados"**.
2. `PreviewSheet` mostra, por item: comando exato, usuário afetado, reversibilidade.
3. Confirmação: `Seguro` = 1 clique; `Atenção` = 1 clique + aviso; `Perigoso` = bloqueado.
4. Execução sequencial com timeout; resultado por item (sucesso/falha + motivo).
5. Tudo registrado no histórico.

**Guardas obrigatórias:**
- Whitelist de caminhos; negar qualquer coisa fora dela.
- Negar `/System`, `/Library/Apple`, `/usr`, `AssetsV2`, `~/.ssh`, `~/Documents`.
- Nunca matar PID 1, `WindowServer`, `loginwindow`, `launchd`, processos de sistema.
- Não executar `sudo` na v1; ações de sistema só na Fase 5 via helper.
- Verificar se o app está aberto antes de apagar seus dados (pedir para fechar).

---

## 8. Fases e critérios de aceite

Cada fase termina em **gate de aprovação**: eu entrego, você testa, aprovamos e só então sigo.

### Fase 0 — Esqueleto (≈ 30–60 min) ✅
- [x] `Package.swift`, estrutura de pastas, `Info.plist`
- [x] App de barra de menu abre, mostra "Analisar" e uma janela vazia
- [x] `scripts/build.sh` gera `SiftBar.app` assinado ad-hoc
- **Aceite:** ícone na barra, app abre e fecha sem erro. ✅

### Fase 1 — Coleta read-only (≈ 1–2 h) ✅
- [x] Os 7 coletores + `ScanReport` (memória, processos, inicialização, brew, disco, caches, sobras)
- [x] Tela com tabela/contadores; botão Analisar funcional
- [x] Nenhuma ação disponível ainda
- **Aceite:** números conferem com `top`/`df`; scan completo em ~0,9 s. ✅
- **Nota:** login items via `osascript` foram adiados para a Fase 3 (evita prompt de TCC a cada build ad-hoc).

### Fase 2 — Classificação e revisão (≈ 1–2 h)
- [ ] Motor de regras + badges de risco + ordenação por impacto
- [ ] Filtros por categoria/risco; busca
- [ ] Itens "Perigoso" apenas informativos
- **Aceite:** lista compreensível sem ler o código; riscos coerentes com a tabela da seção 6.

### Fase 3 — Ações seguras (≈ 1–2 h)
- [ ] Remover login item, `launchctl bootout`, `brew services stop`
- [ ] Preview + confirmação + resultado por item
- **Aceite:** testar em itens reais reversíveis; histórico registra tudo.

### Fase 4 — Caches e disco (≈ 1–2 h)
- [ ] Cálculo de tamanho com `du`, whitelist, dry-run
- [ ] Exclusão com confirmação e relatório de bytes liberados
- **Aceite:** apagar caches de teste; nenhum caminho fora da whitelist é tocado.

### Fase 5 — Privilégios de admin (≈ 2–4 h, opcional)
- [ ] Helper privilegiado (`SMAppService`) para ações de sistema
- [ ] Diálogo de autorização; comandos auditados
- **Aceite:** ação de sistema funciona com senha e falha limpa se negada.

### Fase 6 — Polimento (opcional)
- [ ] Histórico visual, agendamento (launchd), notificações
- [ ] Ícone próprio, atalho global, modo "só monitorar"
- [ ] Exportar relatório em Markdown

---

## 9. Testes

- **Unitários:** parsing de `vm_stat`, `ps`, `launchctl`, `brew services`; regras de risco; whitelist.
- **Integração:** cada coletor contra dados reais; `CommandRunner` com timeout e argumentos inválidos.
- **Segurança:** tentar path traversal, caminho fora da whitelist, PID protegido, injeção de argumento.
- **Manual:** comparar números com Atividade do Monitor, `top`, `df` e `launchctl list`.

---

## 10. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Sem Xcode, algo não compilar | Validado SwiftUI/MenuBarExtra; build via `swiftc` direto |
| TCC bloqueia leitura de `~/Library` | Detectar e exibir aviso; botão para abrir Ajustes |
| Matar processo com trabalho não salvo | Selo "Atenção", nome do app, confirmação explícita |
| Apagar cache em uso | Checar processo aberto e bloquear |
| Números divergirem do Finder | Explicar categoria vs. pasta (lição dos "15 GB em Documentos") |
| App ficar pesado | Coletores com timeout e execução paralela; UI sob demanda |
| Distribuição | v1 é local; notarização só se necessário |

---

## 11. Próximo passo

Aprovar a **Fase 0**. Ao aprovar, eu:
1. crio `Package.swift`, fontes mínimas e `Info.plist`;
2. crio `scripts/build.sh` e `scripts/run.sh`;
3. compilo, assino ad-hoc e abro o app para você ver o ícone na barra.

> Nome "SiftBar" é provisório. Se quiser outro (ex.: MacTune, Sentinel, TuneBar), digo onde trocar — é só o nome da pasta, do target e do bundle ID.
