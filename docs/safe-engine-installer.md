# Recuperare sigură a engine-ului Nova Cortex

Acest ghid este pentru o instalare care s-a oprit sau pentru o actualizare controlată. Nu publică nimic, nu migrează date și nu demonstrează funcționarea pe Windows. Păstrează `.env`, organizațiile, memoriile, crons, backup-urile și stash-urile; nu rula `git reset`, `git clean`, `git stash`, `pm2 resurrect` sau `pm2 save` ca remediere automată.

## Cele patru comenzi ale helper-ului

Rulează din checkout-ul Nova, cu Node-ul utilizatorului:

```powershell
node .\scripts\nova-engine.mjs prepare
node .\scripts\nova-engine.mjs check
node .\scripts\nova-engine.mjs start --org NUME_ORG --channel telegram
node .\scripts\nova-engine.mjs save
```

Pe macOS/Linux, separatorii sunt `/`; formele comenzilor sunt aceleași. `prepare` este singura comandă care poate clona, face fetch/fast-forward, instala dependențe, compila și relinka engine-ul. `check` este numai citire: verifică proveniența, receipt-ul de build, artefactele și link-ul. `start` verifică din nou engine-ul și runtime-ul, apoi pornește daemonul nou sau cere confirmare înainte de a reporni daemonul selectat. `save` validează din nou runtime-ul înainte de snapshot.

Nu înlocui `start` cu `cortextos start boss`: helper-ul nu are fallback automat către CLI-ul upstream, deoarece acel traseu poate ocoli verificările de runtime/snapshot. Pentru Slack, wizardul pornește bridge-ul numai după `start`; nu porni manual alte procese pentru a „face să treacă” verificarea.

## Pinul și limitele actualizării

Release-ul acceptat este SHA `ee7f06f2ad687237db670118f6cdf7c6792c1572`, obținut din `refs/heads/fix/windows-telegram-submit-main-integration` al repository-ului canonic al installerului: `https://github.com/danutmitrut/cortextos.git`. Nu presupune că acest hotfix este în `main` și nu schimba pinul pentru a urma automat `main`.

Un repo existent este acceptat numai dacă remote-ul său indică repository-ul canonic; numele remote-ului poate fi `upstream`, nu trebuie să fie `origin`. Helper-ul permite numai fast-forward spre pin. Un HEAD divergent, mai nou decât pinul, sau cu proveniență incertă se oprește fără downgrade și fără rescrierea remote-urilor.

`prepare` refuză orice modificare Git tracked **sau** untracked. Aceasta include template-urile Nova copiate de un wizard anterior. Nu există stash, reset, clean, ignorare automată sau suprascriere de template. Oprește-te, păstrează conținutul și cere operatorului să inspecteze fiecare cale afișată înainte de a decide ce se păstrează ori se mută în afara checkout-ului. Reia doar după ce checkout-ul este curat în mod intenționat.

Un update al codului nu este o migrare de date. Dacă `prepare` actualizează sursa dar build-ul sau link-ul eșuează, nu repornește daemonul și nu face rollback automat. Mesajul raportează SHA-ul sursei și ultima compilare reușită; remediază build-ul/link-ul, apoi rulează din nou `prepare`. Nu trata ultima compilare reușită ca build al noului SHA.

## Căi de verificat, fără a expune secrete

În mod implicit engine-ul este `~/cortextos` (sau `%USERPROFILE%\cortextos`), iar starea instanței este `~/.cortextos/default` (sau `%USERPROFILE%\.cortextos\default`). `CORTEXTOS_DIR` poate seta explicit engine-ul; `PM2_HOME` poate seta explicit directorul PM2. Receipt-ul de build este în metadatele Git ale engine-ului, la calea calculată de Git pentru `nova-installer/build.json`.

Păstrează mesajele helper-ului și căile scurte afișate de el. Pentru diagnostic, comunică numai codul de refuz, calea engine-ului, SHA-ul cerut/găsit și dacă build-ul a reușit. **Nu trimite în chat tokenuri, fișiere `.env`, certificate private, `pm2 jlist`, dump-uri PM2 brute sau mediul complet al unui proces.** Dacă sunt necesare loguri, redactează credențialele și folosește numai liniile relevante.

Pe Windows, npm, PM2 și CortextOS pot fi wrapper-e `.cmd`; rulează comenzile PowerShell cu calea `.cmd` rezolvată de sistem și operatorul `&`. Nu redenumi wrapper-ele în `.ps1` și nu modifica Execution Policy pentru acest flux sau pentru testele lui.

## CA, PM2 și recuperare

Folosește numai `NODE_EXTRA_CA_CERTS` configurat explicit de operator. Dacă este prezent, trebuie să fie cale absolută către un PEM valid; helper-ul îl transmite daemonului selectat și verifică mediul efectiv. Nu importa automat certificate, nu opri antivirusul pentru a ocoli TLS și nu seta `NODE_TLS_REJECT_UNAUTHORIZED=0`. O verificare TLS fără token este doar diagnostic; nu dovedește că Telegram a făcut polling cu succes.

`pm2 save` salvează un snapshot PM2, nu configurează un serviciu Windows la boot. Helper-ul cere acord înainte de un restart care întrerupe agenți și înainte de un snapshot global care include aplicații fără legătură. Nu folosește `pm2 all`, nu salvează o listă goală și nu restaurează automat dump-uri.

Dacă lista PM2 este goală iar `dump.pm2` sau `dump.pm2.bak` există, este nevoie de revizuire operator: identifică proprietarul, calea, interpreterul, instanța și impactul asupra aplicațiilor nelegate înainte de orice restaurare. Nu rula `resurrect` sau `save` până nu există o decizie explicită. O instalare nouă fără dump poate crea numai daemonul așteptat.

## Ce înseamnă „pregătit”

Un `prepare` reușit înseamnă sursă și build validate; nu înseamnă că datele au fost migrate sau că agentul comunică. Un `start` reușit verifică runtime-ul selectat, însă schimbul real de mesaje rămâne test de acceptare separat. `save` reușit înseamnă „salvat pentru restaurare”; pornirea automată după reboot Windows este încă neverificată până la testul controlat de mai jos.

Pentru un test Telegram, folosește un marker unic fără secrete: trimite un mesaj scurt cu markerul, apoi unul lung, multiline și cu emoji. Înregistrează exact un inbound, blocul vizibil de mesaj nou, pornirea unui turn real și outbound-ul corelat. Cere aprobarea explicită înainte de reboot; după reboot verifică același build, root și CA, apoi repetă testul.
