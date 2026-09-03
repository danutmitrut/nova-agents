# Installer Nova Cortex: engine verificat și TLS/PM2 pe Windows

Data: 2026-09-03. Status: politică aprobată în conversație; document pentru aprobarea finală, înainte de plan și cod.

## Obiectiv

Reinstalarea sau reluarea configurării Nova nu trebuie să lase cursantul pe un engine vechi doar pentru că există comanda `cortextos`. Installerul trebuie să identifice instalarea reală, să instaleze/actualizeze o versiune validată și să raporteze separat starea codului, build-ului și procesului pornit. Pe Windows, transmite către daemon configurația CA deja aprobată de utilizator, fără relaxarea verificării TLS.

Nu schimbăm onboarding-ul, memoria, baza de date, tokenurile sau comportamentul conversațional al agenților. Nu introducem alte remedieri PTY în acest proiect.

## Dovezi și limita lor

- În `nova-prereq.ps1` și `nova-prereq.sh`, existența comenzii `cortextos` ocolește instalarea și verificarea engine-ului. În plus, `nova-init.ps1` sare peste prerequisites dacă găsește comanda.
- Bootstrap-ul engine-ului citește un branch la clonare, dar la actualizarea unui repo existent poate executa `git pull upstream main --ff-only`; la eșec continuă cu versiunea existentă. Simpla setare a branch-ului nu rezolvă problema.
- Verificarea remote din 2026-09-03: Nova `main` este `747e3ac316acd059bc5d3485371611dcbabce671`; CortextOS `main` este `f7b0c964dd2a5e860234dc981bcb50fe42c34c0d`. Hotfixul este separat, pe `fix/windows-telegram-submit-main-integration`, la `ee7f06f2ad687237db670118f6cdf7c6792c1572`.
- Conform raportului Dorinei, hotfixul a trecut un test Telegram capăt-la-capăt și o conversație nouă coerentă. Persistența după reboot și mesajele lungi necesită încă verificare formală; nu sunt declarate demonstrate de acest document.

## Decizia de produs

Au fost comparate trei variante: versiune exactă validată, ultima versiune din `main`, respectiv avertizare fără actualizare. Alegerea aprobată este versiunea exactă: instalări reproductibile, cu actualizarea deliberată a versiunii publicate. Urmărirea automată a `main` ar introduce schimbări neverificate; avertizarea singură ar păstra problema cursantului.

Manifestul Nova va conține URL-ul canonic `https://github.com/danutmitrut/cortextos.git`, un ref de descărcare și SHA-ul complet acceptat. Candidatul inițial este `ee7f06f2ad687237db670118f6cdf7c6792c1572`. Instalarea validează SHA-ul, nu doar numele branch-ului. Nu presupune că hotfixul este în `main` și nu face merge/publicare automat. Publicarea installerului este o etapă separată de implementarea locală.

## Componente și integrare

1. Un manifest de versiune și un helper Node comun pentru identificare, verificări Git, actualizare și build. Node este deja prerequisite. Helperul folosește argumente explicite pentru procese, nu concatenarea intrărilor în comenzi shell.
2. `nova-prereq.ps1` și `nova-prereq.sh` apelează aceeași politică după verificarea dependențelor, chiar dacă există comanda globală. Nu mai execută bootstrap-ul mobil din `main` pentru operațiile de instalare/actualizare a engine-ului.
3. Ambele variante `nova-init` trec prin preflight înainte de copierea template-urilor, modificarea configurației sau pornirea agenților. Wizardul existent, inclusiv alegerea runtime-ului și canalului, rămâne neschimbat în afara acestor verificări.
4. Integrarea Windows PM2 verifică mediul și procesul țintă la pornire/restart. Comenzile npm/PM2/CortextOS lansate din PowerShell folosesc wrapper-ele `.cmd` când sunt instalate astfel; nu schimbăm Execution Policy.

## Contractul instalării și actualizării

- Calea țintă este `CORTEXTOS_DIR` explicit, altfel directorul implicit al utilizatorului. Se compară cu destinația comenzii globale și cu scriptul/cwd ale daemonului existent. Neconcordanțele opresc operația și afișează căile; nu se alege arbitrar între instalări.
- Dacă ținta lipsește, clonăm repo-ul canonic și rezolvăm commit-ul din manifest înainte de instalarea dependențelor, build, link sau pornire. Nu executăm întâi o altă versiune de bootstrap.
- Dacă există, trebuie să fie repo Git al engine-ului așteptat. Remote-ul se identifică după URL, fără presupunerea numelui `origin`; `upstream` este acceptat. Nu redenumim sau înlocuim automat remote-urile utilizatorului.
- Orice modificare tracked sau fișier untracked oprește actualizarea, inclusiv template-uri locale copiate anterior. Raportul enumeră căile relevante și cere intervenție explicită. Nu facem stash/reset/clean și nu ascundem modificările cu reguli Git noi.
- Dacă HEAD este chiar versiunea acceptată, verificăm instalarea/build-ul fără a schimba istoricul. Dacă HEAD este un strămoș al versiunii acceptate, actualizăm exclusiv fast-forward. Istoricul divergent, versiunea mai nouă decât pin-ul sau proveniența incertă opresc fluxul; nu facem downgrade și nu presupunem că orice versiune mai nouă este validată.
- Eșecul fetch, verificării SHA, instalării dependențelor sau build-ului este fatal pentru acest flux. Nu continuăm onboarding-ul și nu declarăm succes folosind versiunea veche.
- Scripturile engine-ului și instalarea dependențelor se execută numai după verificarea checkout-ului, folosind manifestul și lockfile-ul acelei versiuni. Build-ul și link-ul trebuie să aparțină aceleiași căi/SHA. Verificăm artefactele înainte de restart și înregistrăm proveniența build-ului; simpla prezență a trei șiruri în `dist/daemon.js` nu este suficientă.
- Dacă build-ul eșuează după fast-forward, raportăm separat că sursa a fost actualizată și build-ul nu este gata. Nu repornim daemonul și nu facem rollback automat. Păstrăm ultima dovadă de build reușit, fără a o eticheta drept build al noului HEAD.
- Datele de instanță, memoria, `.env`, crons, backup-urile și stash-urile nu se șterg și nu se migrează. Variabilele temporar suprascrise de installer sunt restaurate la valoarea inițială, nu șterse necondiționat.

## TLS și PM2 pe Windows

- Folosim numai `NODE_EXTRA_CA_CERTS` deja configurat explicit de utilizator. Verificăm calea absolută, existența, accesul și parsarea certificatelor PEM. Nu instalăm root-uri, nu extragem automat certificate Avast și nu considerăm un certificat sigur doar fiindcă se poate parsa.
- Dacă variabila lipsește și conexiunile TLS sunt valide, nu adăugăm CA. Dacă există o valoare invalidă sau apar erori de certificate, fluxul oprește etapa de pornire și cere configurare explicită. Nu folosim `NODE_TLS_REJECT_UNAUTHORIZED=0`, dezactivarea antivirusului sau ocolirea validării TLS. Nu adăugăm implicit `--use-system-ca`.
- Citim doar câmpurile necesare din PM2 cu Node, nu cu `ConvertFrom-Json` din PowerShell 5.1, unde cheile de mediu care diferă doar prin majuscule au produs eroare. Nu afișăm dump-ul complet, tokenuri sau mediul complet al proceselor.
- Identificăm utilizatorul, `PM2_HOME`, instanța și daemonul corect înainte de operații. Dacă există procese omonime, căi neconcordante sau indicii ale altei instanțe PM2, oprim și cerem alegerea explicită.
- La prima pornire, transmitem mediul CA validat. La un daemon existent, actualizăm doar procesul identificat, cu `--update-env`, după build reușit și confirmarea scurtei întreruperi. Nu folosim restart/stop/delete pentru toate aplicațiile.
- Helperul Nova controlează pornirea daemonului și momentul salvării. Nu delegăm prima pornire către ramura actuală din `cortextos start`, care execută deja `pm2 save` înaintea verificărilor Nova. Pornirea agentului urmează numai după confirmarea daemonului; dacă acesta dispare între verificări, oprim fluxul, nu intrăm într-un fallback de pornire/salvare neverificat.
- Dacă lista PM2 este goală și există un dump anterior, nu executăm automat `resurrect` sau `save`. Raportăm situația; restaurarea controlată cere verificarea dump-ului și aprobarea utilizatorului. O instalare nouă fără stare anterioară poate crea daemonul așteptat.
- După pornire verificăm calea reală, cwd, starea daemonului, configurația CA din procesul efectiv și bootstrap-ul. O verificare HTTPS fără token, pornită cu același Node și mediu CA, este diagnostic suplimentar, nu dovadă că poller-ul PM2 a reușit.
- Salvăm PM2 numai după verificări pozitive și confirmăm succesul salvării. Nu salvăm o listă goală ori o stare de recuperare incompletă. Dacă sunt și aplicații fără legătură, cerem confirmare pentru snapshot-ul global `pm2 save`; nu le schimbăm configurația.
- Raportul distinge „salvat pentru restaurare” de „pornire automată Windows verificată”. Instalarea unui serviciu de startup Windows și reboot-ul nu se execută implicit.

## Raportul final al installerului

Raport scurt, fără secrete: calea engine-ului, SHA cerut și găsit, build reușit/eșuat, daemon pornit sau restart rămas de făcut, CA absent/valid/transmis, PM2 salvat sau motivul nesalvării. Dacă lipsește dovada runtime, nu afișăm „BOSS online”. Testul Telegram se raportează separat de succesul instalării.

## Verificare și criterii de acceptare

- Teste automate cu repo-uri temporare: țintă absentă; versiune exactă; fast-forward; dirty tracked/untracked; divergență; versiune mai nouă; remote `upstream`; remote/cale greșite; fetch și build eșuate. Cazurile de refuz nu șterg date și nu repornesc PM2.
- Teste ale integrării PM2 cu procese simulate: CA prezent/lipsă/invalid, chei `username` și `USERNAME`, listă goală cu dump, proces greșit/ambiguu, aplicații suplimentare, restart eșuat și salvare condiționată. Nu se introduc certificate sau tokenuri reale în fixtures.
- Verificări ale scripturilor pentru ambele platforme și rulare de acceptare pe Windows real, atât PowerShell 5.1 cât și 7. Verificările locale pe macOS nu vor fi prezentate drept validare Windows.
- Acceptare Windows: instalare nouă și actualizare curată; comanda globală deja existentă nu mai sare verificarea; CA ajunge în PM2; un mesaj Telegram scurt și unul lung/multilinie/cu emoji au marker unic, pornesc turn-ul și primesc outbound corelat. Nu deducem injectarea doar din creșterea `stdout.log`.
- După aprobarea unui reboot controlat, repetăm testul Telegram și verificăm CA, calea și build-ul procesului restaurat. Până atunci, persistența după reboot rămâne neverificată.
- Publicarea cere rezultate consemnate și aprobarea separată a modificărilor/release-ului. Nicio modificare la instalarea Dorinei nu rezultă automat din acest proiect.

## Etape și control

- [x] Explorarea codului și a versiunilor remote.
- [x] Clarificarea scopului; comparația celor trei abordări.
- [x] Aprobarea politicii de actualizare sigură și a includerii TLS/PM2.
- [x] Specificație scrisă; verificată pentru contradicții, ambiguități și extindere nejustificată.
- [ ] Aprobarea acestui document de către Dan.
- [ ] Plan de implementare, apoi cod și teste.
- [ ] Acceptare Windows și decizie de publicare.

Companionul vizual nu este necesar pentru aceste decizii. La acest checkpoint se modifică numai documentația; installerul nu este încă reparat.
