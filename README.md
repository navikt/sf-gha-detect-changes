# sf-gha-detect-changes

GitHub action for å oppdage og kategorisere endrede filer i Salesforce-prosjekter.
Resultatet kan brukes til å styre hvilke steg som kjøres i CI.

## Bruk

Sjekk ut repositoryet med full Git-historikk, slik at commitene som sammenlignes er tilgjengelige.
Actionen krever Bash, Git og `jq`, som er tilgjengelige på GitHub-hostede Ubuntu-runnere.
Erstatt `<tag/sha>` med ønsket versjon eller commit-SHA.

<!-- Start usage -->
```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0

- name: Detect changes
  id: changes
  uses: navikt/sf-gha-detect-changes@<tag/sha>
  with:
    # Base commit or branch to compare against (auto-detected if empty)
    # Required: false
    # Default: ''
    base: ''

- name: Handle code changes
  if: steps.changes.outputs.code == 'true'
  run: echo "LWC, Apex eller Trigger er endret"
```
<!-- end usage -->

## Sammenligningsgrunnlag

Actionen sammenligner `github.sha` med følgende grunnlag, i prioritert rekkefølge:

1. Commit eller branch angitt i `base`.
2. Base-commit for pull requesten ved `pull_request`-hendelser.
3. `github.event.before` ved push, dersom verdien er satt og ikke bare består av nuller.
4. Første forelder til `github.sha`, eller et tomt Git-tre hvis commiten ikke har en forelder.

Et eksplisitt `base` kan for eksempel være `origin/main`. Referansen må finnes lokalt.
Git-feil eller ugyldige resultater stopper actionen; de rapporteres ikke som «ingen endringer».

## Kategorier

| Kategori | Filer |
| --- | --- |
| Code | Filer under `force-app/*/lwc/*`, unntatt `*.md`, samt `*.cls`, `*.trigger`, `*.apex`, `*.cls-meta.xml` og `*.trigger-meta.xml` uansett mappe. |
| Metadata | Øvrige `*-meta.xml`-filer under `force-app/`, inkludert Flows. |
| Other | Alle andre filer, inkludert Markdown og Salesforce-filer som ikke matcher kategoriene over. |

Hver fil tilhører én kategori. Flere kategorier kan være endret i samme sammenligning.

## Outputs

| Output | Beskrivelse |
| --- | --- |
| `code` | Strengen `'true'` hvis kodefiler er endret, ellers `'false'`. |
| `metadata` | Strengen `'true'` hvis metadatafiler er endret, ellers `'false'`. |
| `other` | Strengen `'true'` hvis andre filer er endret, ellers `'false'`. |
| `summary` | Endringsoppsummering i Markdown med kategorier og alle endrede filer. |
| `changed_files` | Alle endrede filstier, separert med linjeskift. |
| `code_files` | Endrede kodefiler, separert med linjeskift. |
| `metadata_files` | Endrede metadatafiler, separert med linjeskift. |
| `other_files` | Andre endrede filer, separert med linjeskift. |

Når ingen filer er endret, er alle kategoriflagg `'false'` og fillistene tomme.
Bruk eksplisitt sammenligning med `'true'` i betingelser, som i eksemplet over.
Oppsummeringen skrives også til GitHub Actions sin step summary når `GITHUB_STEP_SUMMARY` er satt.

## Henvendelser

Spørsmål knyttet til koden eller prosjektet kan stilles som issues her på GitHub.

## For NAV-ansatte

Interne henvendelser kan sendes via Slack i kanalen #platforce.
