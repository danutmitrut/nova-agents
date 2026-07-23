# Permisiunile agenților: cine aprobă ce

Două situații te aduc pe pagina asta:

- **„Agentul face orice fără să ceară voie"** , da, așa e setat din fabrică. Agenții Nova Cortex rulează autonom (heartbeat-uri, cron-uri de noapte, task-uri lungi), iar un agent care așteaptă aprobare la fiecare pas nu poate lucra nesupravegheat. Nu e un bug, e modul implicit.
- **„Vreau să-mi ceară aprobare pe telefon înainte de acțiuni"** , se poate, pe Telegram, cu rețeta completă de mai jos. Ambii pași sunt obligatorii, unul singur nu face nimic vizibil.

## Cum funcționează de fapt: trei straturi

Permisiunile trec prin trei straturi, în ordinea asta. Fiecare strat contează doar dacă stratul de deasupra îl lasă să intre în joc.

**Stratul 1: `dangerously_skip_permissions` în config.json** (domină tot)

Fiecare agent are `~/cortextos/orgs/<org>/agents/<agent>/config.json` (pe Windows: `C:\Users\<tu>\cortextos\orgs\...`). Câmpul `dangerously_skip_permissions` decide dacă agentul pornește cu sistemul de permisiuni al lui Claude Code anulat complet:

- `true` sau lipsă = autonom: nicio unealtă nu cere vreodată permisiune, straturile 2 și 3 sunt scoase din circuit
- `false` (boolean, NU `"false"` cu ghilimele, valorile non-boolean sunt tratate ca `true`) = gate-ul de permisiuni pornește

**Stratul 2: lista `allow` din `.claude/settings.json`** (contează doar cu gate-ul pornit)

În folderul agentului, `.claude/settings.json` pre-aprobă din template uneltele: Bash, Read, Edit, Write, WebFetch, WebSearch. Cu gate-ul pornit, uneltele din lista asta tot NU cer aprobare; doar ce nu e pe listă ajunge la stratul 3. De aceea pasul 2 din rețetă e obligatoriu: dacă lași Bash și Write în listă, nu vei primi nimic pe telefon.

**Stratul 3: aprobarea pe Telegram** (ce trece de straturile 1 și 2)

Cererea ajunge pe telefon ca mesaj cu butoane Approve/Deny. Dacă nu răspunzi în 30 de minute, cererea e refuzată automat și agentul merge mai departe fără acțiunea aia. Scrierile agentului în propriul folder `.claude/` se auto-aprobă (altfel s-ar bloca pe fișierele lui interne).

## Rețeta: mod supravegheat cu aprobări pe Telegram

Condiție prealabilă: agentul are Telegram configurat (`BOT_TOKEN` și `CHAT_ID` în `.env`-ul agentului). Hook-urile de aprobare sunt momentan doar pe Telegram; pe un setup Slack-only NU porni gate-ul, cererile ar fi refuzate silențios în lipsa credențialelor Telegram.

1. În `config.json` al agentului, setează:

   ```json
   "dangerously_skip_permissions": false,
   ```

2. În `.claude/settings.json` al agentului, scoate din lista `allow` uneltele pentru care vrei aprobare. Recomandat: scoate `Bash`, `Edit`, `Write` (acțiunile cu efect), păstrează `Read`, `WebFetch`, `WebSearch` (doar citesc).

3. Repornește agentul ca să recitească config-ul:

   ```
   cortextos restart <agent>
   ```

4. Testează: cere-i agentului să creeze un fișier. Pe telefon trebuie să apară cererea cu Approve/Deny; fără aprobare, fișierul nu se creează.

## Avertismente oneste, înainte să alegi

- **Costul modului supravegheat:** fiecare acțiune gate-uită așteaptă telefonul tău, maxim 30 de minute, apoi e refuzată automat. Un agent cu cron-uri de noapte se va lovi de refuzuri cât dormi. Alege per agent, nu global: de exemplu supravegheat pe agentul care atinge lucruri sensibile, autonom pe restul.
- **`working_directory` NU e gard de protecție.** E doar folderul în care pornește agentul (gol = folderul agentului). Cu modul autonom activ, Bash și Write pot acționa oriunde pe mașină, indiferent de `working_directory`. Singurul gard real e rețeta de mai sus.
- **Se aplică doar runtime-ului claude-code.** Agenții pe runtime codex au alt mecanism; câmpul ăsta nu are efect la ei.

## Care mod pentru cine

- **Autonom (implicit):** rutina de încredere a org-ului, agenți care lucrează noaptea, demo-uri de curs. Riscul îl gestionezi prin ce scrii în GUARDRAILS.md și prin ce acces are mașina.
- **Supravegheat:** agenți care ating date sensibile, bani, conturi reale, sau perioada în care încă înveți ce face un agent nou. Ține telefonul aproape.
