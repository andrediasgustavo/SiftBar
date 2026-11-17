# Regras do projeto para agentes de IA

Estas regras valem para qualquer agente que trabalhe neste repositório.

## Git: nunca commitar nem pushar sem pedido explícito

- **NÃO** rode `git commit`, `git push`, `git tag` ou equivalente por conta
  própria — nem "para fechar a tarefa".
- Só commite/pushe quando a instrução do usuário **na mesma mensagem** pedir
  isso de forma explícita (ex.: "commita", "faz o push", "pode subir").
- Terminar uma implementação não é autorização para commitar. Deixe as
  mudanças no working tree e informe o que está pendente.
- Na dúvida, pergunte antes.

## Mudanças no sistema e no app

- Analyze é **read-only**; nada no Mac muda sem confirmação explícita do
  usuário.
- Nunca rodar `sudo`/ações administrativas; nunca apagar dados sem pedido.
- Antes de substituir/instalar o app em `/Applications`, fechar a instância
  em execução e verificar a assinatura depois.

## Qualidade

- O hook de pre-commit roda só `./scripts/test.sh` (unit). XCUITest fica no
  CI/nightly ou pode ser rodado manualmente com `./scripts/check.sh`.
- O gate completo (unit + XCUITest) precisa estar verde antes de merge/release.
- **Nunca enfraqueça ou apague testes/gates para fazer o CI passar.** Não apague, ignore,
  reescreva ou afrouxe testes, workflows, `scripts/check.sh`, `scripts/test.sh`
  ou whitelists para obter verde. Mudanças em `Tests/`, `.github/`, `scripts/`,
  `Package.swift`, `project.yml` e `Resources/Info.plist` exigem pedido
  explícito e revisão humana.
- **Sem dependências externas sem aprovação.** O app não tem pacotes Swift
  externos; `scripts/check-dependencies.sh` precisa passar. Não adicione
  `.package(...)` nem `Package.resolved` por conta própria.
- Testes de UI usam Page Objects (`Tests/XCUITests/Pages`) e accessibility IDs;
  não reintroduza testes baseados em OCR.
- Atualize `HANDOFF.md`/`CONTEXT.md` (locais, ignorados pelo git) a cada
  mudança relevante.

## Respostas

- O usuário fala português; o app e os docs de usuário são em inglês.
- Seja direto ao reportar problemas e trade-offs.
