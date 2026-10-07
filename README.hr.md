# HelpdeskToolkit

[![CI](https://github.com/Majstor767/HelpdeskToolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/Majstor767/HelpdeskToolkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE)

*English version: [README.md](README.md)*

Dijagnostički alat za Windows računala, namijenjen radu u helpdesku i IT podršci. Jednim
klikom ili jednom naredbom provjeri stanje računala i napravi pregledan izvještaj s
pronađenim problemima i preporukama što učiniti.

- **Samo čita.** Provjere samo čitaju podatke i nikad ništa ne mijenjaju na sustavu.
  Alat zapisuje samo svoje: postavke, izvještaje i, ako označiš "Start with Windows",
  jedan prečac u tvojoj mapi Startup. Jedino što može pokrenuti, a da mijenja računalo,
  jest deinstalacija programa koji klikneš u popisu zauzeća diska, i to tek nakon tvoje
  potvrde.
- **Ne traži administratorska prava.** Provjere kojima trebaju preskače i označava s "Requires admin".
- **Ne traži ništa osim samog alata.** Napisan je u PowerShellu i koristi ono što Windows već ima.

Prozor se može prebaciti na hrvatski (stranica **Settings**). Izvještaji i naredbe su na
engleskom, pa su i nazivi u ovom dokumentu navedeni onako kako pišu na engleskom.

![Obilazak prozora aplikacije](docs/demo.gif)

## Što provjerava

| Kategorija | Provjere |
|---|---|
| System | Ime računala, verzija i build Windowsa, ima li ta verzija još Microsoftovu podršku, datum instalacije, proizvođač i model, domena ili radna grupa, prijavljeni korisnik, vremenska zona, uptime, indeks stabilnosti, aktivacija Windowsa, programi koji se pokreću sa sustavom, zakazani zadaci koji nisu dio Windowsa, plan napajanja, Fast Startup, trajanje zadnjeg pokretanja\*, veličina korisničkih profila\*, spremnost za Windows 11 (na Windowsu 10, sa svakim zahtjevom posebno), zadnji rezultat System File Checkera, što je Windows okrivio za sporo pokretanje\* |
| Specifications | Procesor s veličinom cache memorije i stanjem virtualizacije, raspored memorije i slobodni utori, svaki memorijski modul (utor, brzina, proizvođač, kataloški broj), grafičke kartice s memorijom i datumom drivera, monitori, fizički diskovi s verzijom firmwarea, optički pogoni, audio uređaji, tipkovnice i pokazivački uređaji, matična ploča, BIOS/UEFI, serijski broj, savjet za stari BIOS, gdje se provjerava jamstvo |
| Hardware | Opterećenje CPU-a, zauzeće RAM-a i najveći potrošači memorije, zdravlje svakog fizičkog diska, slobodan prostor po disku (disk na kojem je Windows je označen, a pun podatkovni disk dobiva drugačiji savjet nego pun disk s Windowsom), najveće mape na disku koji se puni, prostor koji se može osloboditi (privremene datoteke, Downloads, koš za smeće), datoteka hibernacije, page file, uređaji bez ispravnog drivera, nepotpisani driveri, stari driveri, napunjenost i zdravlje baterije (preostali kapacitet u odnosu na novu bateriju), detalji diska (temperatura, istrošenost, sati rada, neispravljene greške)\*, diskovi označeni za provjeru\*, privremene datoteke Windowsa\*, rezultat zadnjeg testa memorije |
| Software | Instalirani programi s verzijama, nedavno instalirani programi, rušenja aplikacija po programu, proširenja preglednika, zadani preglednik, programi koji više ne dobivaju sigurnosna ažuriranja, programi koji su još na popisu iako im je program za deinstalaciju nestao, programi za koje postoji novija verzija (pita se winget), Microsoft Office s kanalom ažuriranja, veličina Outlook datoteka s poštom |
| Event Log | Neočekivana gašenja, plavi ekrani, greške diska, greške hardvera (WHEA), kritični događaji i greške u System i Application logu u zadnjih N dana, najčešći izvori |
| Windows Update | Zadnje instalirano ažuriranje, ažuriranja koja čekaju instalaciju, ažuriranja koja se nisu uspjela instalirati, čeka li se restart, jesu li ažuriranja pauzirana |
| Security | Zaštita u stvarnom vremenu, starost definicija, zaštita od neovlaštenih izmjena, zadnje skeniranje i povijest prijetnji Microsoft Defendera, firewall profili, User Account Control, Remote Desktop, vrsta računa, članovi grupe Administrators, automatska prijava, lokalni računi i račun Guest, dijeljene mape, portovi otvoreni prema mreži i programi koji na njima slušaju, sigurnosne kopije (File History, OneDrive, System Restore), Secure Boot, TPM\*, BitLocker na svakom disku\*, neuspjele prijave\*, zaključani računi\*, točke vraćanja\*, SmartScreen, integritet memorije (Core isolation), LSA zaštita, SMB 1.0, automatsko zaključavanje zaslona, programi koji su koristili kameru, mikrofon i lokaciju, USB memorije koje su bile spojene |
| Network | Adapteri (IPv4, gateway, DNS, DHCP, MAC, brzina veze), jačina signala, pojas, standard i zaštita Wi-Fi mreže, mrežni profil, proxy, hosts datoteka, mapirani mrežni diskovi, ping gatewaya i interneta, DNS razlučivanje, HTTPS pristup, točnost sata |
| Printers | Zadani pisač, instalirani pisači i oni koji su offline, dokumenti zaglavljeni u redu za ispis |
| Services | DHCP Client, DNS Client, Windows Event Log, Workstation, Windows Defender Firewall, Microsoft Defender Antivirus, Windows Update, BITS, Print Spooler te servisi koji nisu dio Windowsa |

\* traži administratorska prava; inače je označeno s "Requires admin". Vidi [Administratorska prava](#administratorska-prava).

Svaki rezultat ima status (**OK**, **Warning**, **Critical** ili **Info**) i kratko
objašnjenje što je to što se provjerava. Rezultat sa statusom Warning ili Critical
dodatno kaže **zašto je to problem**, odnosno do čega dovodi ako se ostavi kako jest,
i ima preporučeno rješenje. Uz mjerenja se prikazuju i dopušteni raspon te tipična
vrijednost za usporedbu.

### Usporedba s drugim alatima

Provjere su uspoređene s onim što prikazuju drugi alati: Microsoft PC Health Check,
Windows Security, alati proizvođača računala (Dell SupportAssist, Lenovo Vantage, HP
Support Assistant), CCleaner Health Check, Microsoft PC Manager, CrystalDiskInfo, HWiNFO,
Belarc Advisor i Reliability Monitor. Preuzeto je ono što pomaže pronaći uzrok
problema, svaki put s razlogom i rješenjem uz rezultat:

| Viđeno u | Preuzeto kao |
|---|---|
| PC Health Check | Spremnost za Windows 11 sa svakim zahtjevom po imenu, a ne samo "da" ili "ne"; što je usporilo pokretanje, a ne samo koliko je trajalo |
| Windows Security | SmartScreen, integritet memorije i LSA zaštita kao provjere, s gumbom koji otvara tu stranicu |
| Alati proizvođača | Gumb koji otvara stranicu podrške proizvođača i kopira serijski broj; savjet za stari BIOS; rezultati testa memorije i System File Checkera |
| CCleaner, PC Manager | Programi s novijom verzijom i programi bez podrške, kao popis; alat ništa ne ažurira i ne uklanja |
| Belarc Advisor | USB memorije koje su bile spojene; koji su programi koristili kameru i mikrofon |
| Reliability Monitor | Stranica **Timeline**: promjene i kvarovi na jednoj vremenskoj crti |
| HWiNFO | Snimanje Live monitora u CSV datoteku, sada i s vremenom odgovora mreže |

Namjerno izostavljeno:

- **Čistači registryja, "RAM boosteri" i gumb "popravi sve".** Mijenjaju sustav, korist
  im je upitna, a alat samo čita.
- **Brzine ventilatora, naponi i temperatura procesora.** Traže vlastiti kernel driver,
  što je sigurnosni rizik i ne ide bez administratorskih prava.
- **Samostalno ažuriranje, reklame i slanje podataka.** Na mrežu idu jedino mrežni
  testovi i upit wingetu, a oboje se isključuje kvačicom "Skip network tests".

## Prozor

![Stranica Overview](docs/screenshot-window.png)

Pri pokretanju aplikacija postavi jedno pitanje: pokrenuti s administratorskim pravima
ili bez njih? Nakon odgovora provjera se pokreće sama. Kategorije se provjeravaju
istovremeno, pa provjera obično traje 10 do 20 sekundi; traka napretka pokazuje koliko
ih je gotovo. Ako je aplikacija već korištena, rezultati zadnje provjere odmah su na
ekranu i zamijene se čim nova provjera završi.

- **Yes** ponovno pokreće aplikaciju s administratorskim pravima (Windows prvo traži
  potvrdu) i ondje pokreće provjeru, uključujući sve što Windows prikazuje samo
  administratorima.
- **No** odmah pokreće provjeru sa standardnim pravima; provjere kojima treba više
  označene su s "Requires admin".

Odgovor se može zapamtiti i kasnije promijeniti na stranici Settings. Nakon te prve
provjere aplikacija sama održava rezultate ažurnima; **Run check** (F5) pokreće je
ponovno u bilo kojem trenutku. Opcije pokraj gumba ("Skip network tests" i broj dana
povijesti) također se pamte do sljedećeg pokretanja.

![Pitanje pri pokretanju](docs/screenshot-start.png)


- **Overview** prikazuje sve probleme s preporučenim rješenjem. Uz rješenje stoji gumb
  koji otvara mjesto u Windowsu gdje se ono provodi (**Open Storage settings**,
  **Open Task Manager**, **Open Windows Update**, ...). Gumb samo otvara tu stranicu;
  samu promjenu uvijek radi osoba za računalom.
- **Health score** od 0 do 100 sažima provjeru u jedan broj: svaki rezultat Critical
  oduzima 15 bodova, a svaki Warning 4. Redak ispod pločica kaže kamo su bodovi otišli
  ("Points lost: Security -19, Software -8"), pa se broj može pročitati.
- **Health score over time** crta ocjenu zadnjih provjera kao liniju, pa se na prvi
  pogled vidi ide li računalu na bolje ili na gore.
- **Since the last check** pokazuje što je novo, gore, bolje ili riješeno u odnosu na
  prethodnu provjeru istog računala. Aplikacija za to čuva zadnjih 30 izvještaja.
- **Timeline** prikazuje što se na računalu događalo zadnjih tjedana, grupirano po
  danima: instalirani, ažurirani i uklonjeni programi, ažuriranja, driveri, a uz njih
  rušenja, neuspjela ažuriranja, plavi ekrani i neočekivana gašenja. Većina traženja
  kvara počinje s "prošli tjedan je radilo"; promjena koja je došla neposredno prije
  prvog kvara obično je uzrok. Filtar ostavlja samo probleme ili samo promjene.
- **Bočna traka:** složena kao navigacija u Windowsu 11. Prvo dolaze stranice
  aplikacije (Overview, Live monitor, Timeline), zatim kategorije provjere pod naslovom
  *Checks*, svaka sa svojom ikonom; broj uz kategoriju je broj problema u njoj, crven
  kad je neki od njih kritičan. Ispod su radnje za izvještaj, a na dnu administratorska
  prava i postavke, koje u niskom prozoru ostaju vidljive dok se ostatak pomiče.
- **Stranica kategorije:** prvo dolaze problemi, svaki preko cijele širine: lijevo što
  je nađeno i zašto je to važno, desno rješenje sa svojim gumbom. Sve što ne traži
  pažnju slijedi kao pločice u tri stupca, s točkom u boji statusa; klik na pločicu
  otvara objašnjenje i dopušteni raspon. Brojači na vrhu pokazuju koliko rezultata
  ima koji status, a klik na jedan ostavlja na stranici samo taj status.
- **Najteže prvo:** gdje god su rezultati poredani jedan ispod drugoga (Overview,
  pretraga, izvještaj), idu redom Critical, Warning, OK, Info.
- **Pretraga** traži po svim rezultatima odjednom, a filtar statusa sužava popis, na
  primjer samo na probleme.
- **Što ovo znači i kako se popravlja:** ispod preporučenog rješenja svakog rezultata
  Warning i Critical nalazi se link na Microsoftovu stranicu koja objašnjava problem
  (oslobađanje prostora, problemi s Windows Updateom, plavi ekran, vatrozid, pisači
  i tako dalje); problem bez takve stranice dobije web pretragu svog naziva.
  Stranica se otvara u tvom pregledniku i ondje gdje sam Windows ne uspijeva otvoriti
  linkove jer kao zadani preglednik i dalje navodi onaj koji je uklonjen; taj se
  slučaj prijavljuje kao zasebno upozorenje pod Software.
- **Link za točno tu grešku:** gdje rezultat navodi ažuriranje ili kod greške, uz
  rješenje stoji link za svaki: Microsoftov članak o ažuriranju koje nije uspjelo
  ("About update KB5050009"), pretraga koda greške Windows Updatea ("0x80070005"),
  stop-koda plavog ekrana ("0x0000009F", popisan pod "Show more" s brojem
  ponavljanja) i koda koji Device Manager daje uređaju koji ne radi ("code 28"). U
  adresu ide samo broj ili kod, nikad ime.
- **Događaji s brojevima:** rezultati dnevnika događaja pod "Show more" listaju svaku
  vrstu greške s izvorom, brojem događaja i koliko se puta dogodila ("Event 10016:
  DistributedCOM (45x)"). Klik na redak pretražuje web točno za taj događaj; tako se
  sazna što znači i kako se popravlja.
- **Copy summary** stavlja kratak tekstualni sažetak u međuspremnik, spreman za
  lijepljenje u ticket ili e-mail.
- **Open HTML report** sprema izvještaj i otvara ga u pregledniku, a **Save as...** ga
  sprema kao HTML, PDF, CSV ili JSON na mjesto koje odabereš.

### Automatska provjera i obavijesti

Provjera se ponavlja u pozadini svakih pet minuta (razmak se u postavkama može
promijeniti ili isključiti). Novi rezultati zamjenjuju stare bez prekidanja: otvorena
stranica, pretraga i mjesto do kojeg si listao ostaju kakvi jesu. Ponovljena provjera
traje samo nekoliko sekundi: jedino što se sporo mjeri, a sporo se i mijenja, veličine
najvećih mapa, mjeri se ponovno svakih pola sata umjesto svaki put.

Gdje provjera košta više nego što donosi, ponavlja se rjeđe: najviše svakih 30 minuta
dok je prozor skriven pokraj sata, svakih 15 na bateriji, a svakih 60 kad vrijedi
oboje. Sporija postavka ostaje kakva jest, a **Run check** uvijek provjerava odmah.

Problem kojeg prije nije bilo najavljuje se u traci na vrhu prozora, a dok prozor nije
u prvom planu i Windows obavijesti. Klik vodi ravno na rezultat, koji je uokviren da ga
je lako naći. Obavijest nestaje kad je zatvoriš ili kad problema više nema.

![Stranica kategorije do koje je dovela obavijest](docs/screenshot-category.png)

![Stranica Timeline](docs/screenshot-timeline.png)

Tipkovni prečaci:

| Tipka | Radnja |
|---|---|
| `F5` | Pokreni provjeru |
| `Ctrl+F` | Pretraga; `Esc` je briše |
| `Ctrl+O` | Otvori HTML izvještaj |
| `Ctrl+S` | Save as... |
| `Ctrl+Shift+C` | Kopiraj sažetak |
| `Ctrl+M` | Live monitor |
| `Ctrl+,` | Settings |
| `Ctrl+T` | Prebacivanje između svijetle i tamne teme |
| `PrtSc` | Kopiranje slike prozora u međuspremnik |

`PrtSc` postoji zato što aplikacija obično radi s administratorskim pravima: Windows
tada tipke pritisnute u njezinu prozoru ne prosljeđuje programima bez tih prava, pa
prečac alata za snimanje zaslona ne radi dok je prozor u prvom planu. Prozor zato sam
napravi sliku; na njoj je samo prozor, a ne ostatak zaslona.

### U pozadini i s Windowsima

Dvije opcije na stranici **Settings**, obje isključene na početku:

- **Keep running when the window is closed.** Zatvaranje prozora ga tada samo sakrije.
  Aplikacija ostaje kao ikona pokraj sata, ponavlja provjeru i novi problem javlja
  Windows obavijesti. Klik na ikonu ponovno otvara prozor; desni klik nudi *Open*,
  *Run check now* i *Exit*, kojim se aplikacija stvarno gasi. Gumb **Run in
  background** na dnu bočne trake radi isto odmah, bez obzira na ovu opciju.
- **Start with Windows.** Stavlja prečac u mapu Startup tvog korisnika (vidi se pod
  *Startup apps* u Windowsima, gdje se može isključiti kao i svaki drugi). Aplikacija
  se tada pokreće pri prijavi, bez prozora, kao ikona pokraj sata, i provjeru radi sa
  standardnim pravima; dok se Windows pokreće, ništa ne traži administratorska prava.
  Kad opciju isključiš ili aplikaciju deinstaliraš, prečac se uklanja.

Istovremeno radi samo jedna kopija: pokretanje aplikacije dok je pokraj sata vraća
njezin prozor umjesto da otvori drugi.

Aplikacija je napravljena da može ostati otvorena, a da ne opterećuje računalo. Svaka
provjera radi u vlastitom kratkotrajnom procesu, pa se njezina memorija vraća
Windowsima čim završi. Otvoren prozor troši oko 200 MB (oko 250 MB dok radi Live
monitor); skriven pokraj sata vraća ono što mu ne treba i ostaje na oko 15 do 35 MB
radne memorije. Kako, piše pod [Memorija](#memorija).

Ako nešto u prozoru pođe po zlu, prozor ostaje otvoren: greška se zapiše u `app.log`
u mapi aplikacije (**Settings > About > Open the folder**), a statusni redak to kaže.

### Jezik i tema

**Prekidač u zaglavlju** (sunce ili mjesec, `Ctrl+T`) prebacuje prozor iz svijetle u
tamnu temu i natrag, odmah i bez ponovnog pokretanja. Stranica **Settings**, koja se
otvara gumbom sa zupčanikom ispod popisa stranica, nudi još i "Same as Windows" te
prebacuje prozor između engleskog i hrvatskog; novi jezik primjenjuje se pri sljedećem
pokretanju. Izvještaji i naredbe ostaju na engleskom, pa izvještaj izgleda jednako tko
god ga napravio. Aplikacija pamti i veličinu i položaj prozora.

![Tamna tema s hrvatskim prijevodom](docs/screenshot-dark-hr.png)

Postavke i povijest izvještaja čuvaju se u `%LOCALAPPDATA%\HelpdeskToolkit`; na stranici
Settings postoji gumb koji otvara tu mapu. Brisanjem mape aplikacija se vraća na
početno stanje.

## Live monitor

Stranica **Live monitor** u prozoru ne traži provjeru. Prikazuje što računalo radi u
ovom trenutku:

- **Statusne točkice:** pločice procesora, memorije i grafike imaju točkicu. Zelena je
  dok je vrijednost u redu, narančasta kad se približi granici ili stalno raste prema
  njoj, a crvena kad je iznad granice. Uz crvenu točkicu pojavi se trokut upozorenja;
  klik na njega otvara savjete kako vrijednost smanjiti, s imenom programa koji u tom
  trenutku najviše opterećuje.
- **Sve o komponenti:** klik na pločicu Processor, Memory ili Graphics otvara stranicu
  koja ispuni prozor svime što se o toj komponenti može pročitati. Za procesor su to,
  među ostalim, predmemorije, mogućnosti, na što mu odlazi vrijeme i opterećenje svakog
  logičkog procesora; za memoriju svaki modul s kataloškim brojem, utori i page file;
  za grafičku karticu driver, taktovi, programi koji je koriste i spojeni monitori.
  Stranica završava svakim svojstvom koje Windows javlja, pod nazivom koji mu Windows
  daje. `Esc` vraća natrag.
- **Procesor:** ukupno opterećenje s grafom povijesti, takt na kojem stvarno radi
  (uključujući turbo), opterećenje svakog logičkog procesora, broj procesa, niti i
  handleova, vrijeme od pokretanja Windowsa
- **Memorija:** zauzeće s grafom povijesti, dostupna, predmemorirana (cached) i
  rezervirana (committed) memorija, kernel poolovi, zauzeće page filea
- **Grafika:** opterećenje s grafom povijesti, opterećenje po engineu (3D, copy, video
  decode, video encode), vlastita i dijeljena memorija
- **Diskovi:** aktivnost s grafom povijesti, brzina čitanja i pisanja te red čekanja
  svakog fizičkog diska, i zauzeti prostor svakog slova diska (mjerač postaje narančast
  i crven prema istim pragovima kao provjera prostora na disku)
- **Što zauzima prostor:** svako slovo diska može se otvoriti da se vide njegovi najveći
  instalirani programi i mape. Klik na program pita želiš li ga deinstalirati i zatim
  pokreće vlastitu deinstalaciju tog programa, istu koju Windows pokreće iz *Installed
  apps*, i onako kako je Windows pokreće: kao korisnik, i kad prozor ima
  administratorska prava (deinstalacija pokretača igara pokrenuta s većim pravima
  pokaže svoj prozor i zatim ne napravi ništa). Za program bez naredbe za
  deinstalaciju (aplikacija iz Storea) otvara se *Installed apps*, s njegovim nazivom
  kopiranim za polje pretrage. Program čiji program za deinstalaciju više ne postoji
  ne može se deinstalirati; prozor to kaže i otvara *Programs and Features*, gdje
  Windows ponudi da takav unos ukloni s popisa. Gumb otvara stranicu na kojoj se čiste
  datoteke
- **Mreža:** brzina preuzimanja i slanja s grafom povijesti, brzina veze svakog adaptera
  te koliko brzo router i internet odgovaraju na ping. Pločica **Internet** na vrhu
  prikazuje vrijeme odgovora, prosjek i udio izgubljenih odgovora, s vlastitom
  točkicom. Spor ili nijem router upućuje na lokalnu mrežu (Wi-Fi, kabel); router koji
  odgovara dok internet ne odgovara upućuje na pružatelja usluge. Dok je označeno
  "Skip network tests", ništa se ne pinga.
- **Senzori:** temperatura, brzina ventilatora i potrošnja NVIDIA grafičkih kartica;
  termalne zone i baterija na računalima koja ih imaju; temperatura, istrošenost i sati
  rada diskova\*
- **Programi:** oni koji troše najviše procesorskog vremena, najviše memorije te čitaju i
  pišu najviše podataka. Klikom na program vidi se odakle je pokrenut, tko ga je
  napravio, otkad radi i koliko procesa ima.

\* traži administratorska prava.

Alati na vrhu stranice:

- **Pause** zamrzava prikaz, a osvježavanje se može postaviti na 2, 5, 10 ili 30 sekundi.
- **Record to file** zapisuje svako mjerenje u CSV datoteku u `Documents\HelpdeskToolkit`
  tijekom 1, 5, 15 ili 60 minuta. To je odgovor na "ponekad je sporo": snimaj dok
  korisnik radi, pa datoteku pogledaj u programu za tablice. U datoteci su i vremena
  odgovora routera i interneta, pa se vidi je li poziv pucao zbog računala ili zbog
  veze.
- **Upozorenja** se pojave kad procesor, memorija ili disk ostanu iznad 90 % nekoliko
  mjerenja zaredom, ili kad se grafička kartica zagrije iznad 85 °C. Jedan kratki skok
  je normalan i ne izaziva upozorenje.

Gumba koji gasi program namjerno nema, a alat sam ništa ne uklanja: pokaže što zauzima
prostor, a za program nakon pitanja pokrene deinstalaciju koju je dao proizvođač tog
programa. Ta deinstalacija pita još jednom i, gdje joj trebaju, od Windowsa traži
administratorska prava. Program instaliran samo za jednog korisnika nikad se ne pokreće
iz prozora koji radi s administratorskim pravima; umjesto toga otvara se njegova
stranica u Windowsu.

![Stranica Live monitor sa savjetima za punu memoriju](docs/screenshot-monitor.png)

![Sve o procesoru](docs/screenshot-component.png)

![Što zauzima prostor na disku](docs/screenshot-monitor-disks.png)

![Donji kraj stranice Live monitor](docs/screenshot-monitor-details.png)

Isti podaci dostupni su u skriptama kroz `Get-PerformanceSnapshot`.

Odakle dolaze vrijednosti senzora i što namjerno nedostaje:

- Vrijednosti NVIDIA grafičkih kartica čitaju se alatom `nvidia-smi`, koji instalira sam
  NVIDIA driver. Pokreće se iz Windowsove mape `System32` punom putanjom. Kartice drugih
  proizvođača nemaju usporediv alat, pa se za njih prikazuju samo opterećenje i memorija.
- Temperatura procesora, ventilatori matične ploče i naponi se ne prikazuju. Windows ih
  ne daje programima; alati koji ih prikazuju instaliraju vlastiti hardverski driver, što
  ovaj alat namjerno ne radi.

## Administratorska prava

Alat radi bez administratorskih prava. Dio podataka Windows prikazuje samo
administratorima; te se provjere tada preskaču i označavaju s "Requires admin".

Da ih uključiš, odgovori **Yes** kad prozor pita pri pokretanju, kasnije klikni
**Restart as administrator**, ili pokreni PowerShell s "Pokreni kao administrator"
prije korištenja naredbi. Windows traži potvrdu (User
Account Control); alat sam sebi ne može dati ta prava. I s administratorskim pravima
alat samo čita.

Ako se potvrda da računom druge osobe (npr. IT administrator na računalu običnog
korisnika), provjere koje opisuju korisnika (programi pri pokretanju, proxy, mapirani
diskovi, privremene datoteke) opisuju taj račun.

## Izvještaj

HTML izvještaj je jedna samostalna datoteka (bez skripti, ništa se ne učitava s
interneta), pa se može poslati e-mailom ili priložiti uz ticket. Prati svijetlu ili
tamnu temu sustava i ima izgled prilagođen ispisu. Ispod broja rezultata po statusu
piše koja je kategorija odnijela koliko bodova ocjene, a na kraju je vremenska crta
promjena i kvarova.

![HTML izvještaj](docs/screenshot-report.png)

Cijeli primjer s izmišljenim podacima nalazi se u [docs/sample-report.html](docs/sample-report.html)
(preuzmi ga i otvori u pregledniku). Isti podaci u JSON-u:
[docs/sample-report.json](docs/sample-report.json).

Ostali formati:

| Format | Čemu služi |
|---|---|
| JSON | Daljnja obrada i usporedba dviju provjera naredbom `Compare-PCHealthReport` |
| CSV | Program za tablice; jedan redak po rezultatu |
| PDF | Arhiviranje i ispis. To je HTML izvještaj ispisan u datoteku, za što na računalu treba Microsoft Edge ili Google Chrome. |

## Instalacija

### Instalacijski program (preporučeno)

1. Preuzmi `HelpdeskToolkit-Setup-<verzija>.exe` sa stranice [Releases](https://github.com/Majstor767/HelpdeskToolkit/releases).
2. Pokreni ga. Instalira se samo za trenutnog korisnika i ne traži administratorska prava.
3. Pokreni **HelpdeskToolkit** iz Start izbornika.

Instalacijski program nije digitalno potpisan, pa Windows SmartScreen pri prvom
pokretanju prikaže "Windows protected your PC". Odaberi **More info** pa **Run anyway**.
Poruka kaže samo da Windows još ne poznaje izdavača datoteke (certifikat za
potpisivanje plaća se svake godine); o tome što datoteka radi ne govori ništa.
Preuzetu datoteku možeš provjeriti prema `SHA256SUMS.txt` iz istog izdanja:

```powershell
Get-FileHash .\HelpdeskToolkit-Setup-<verzija>.exe -Algorithm SHA256
```

Uklanja se kroz **Postavke > Aplikacije > Instalirane aplikacije**.

### Prijenosni ZIP

1. Preuzmi `HelpdeskToolkit-<verzija>.zip` sa stranice [Releases](https://github.com/Majstor767/HelpdeskToolkit/releases).
2. Desni klik na ZIP, **Svojstva**, označi **Deblokiraj**, pa ga raspakiraj.
3. Dvoklik na `Start-HelpdeskToolkit.cmd`.

### Kao PowerShell modul

```powershell
git clone https://github.com/Majstor767/HelpdeskToolkit.git
cd HelpdeskToolkit
Import-Module .\HelpdeskToolkit\HelpdeskToolkit.psd1
```

Ako PowerShell odbije učitati modul jer je pokretanje skripti onemogućeno, dopusti
lokalne skripte za svoj korisnički račun:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

## Korištenje iz naredbenog retka

`Show-PCHealthCheck` otvara gore opisani prozor (`-NoQuestion` ga otvara bez pitanja i
bez provjere). Sve ostalo radi i bez njega.

```powershell
# Pokreni sve provjere, spremi HTML izvještaj u Documents\HelpdeskToolkit i otvori ga
Invoke-PCHealthCheck

# 30 dana Event Loga, HTML i JSON, spremljeno u mapu po izboru
Invoke-PCHealthCheck -OutputPath C:\Temp\Reports -Days 30 -Format Both

# Bez preglednika i bez mrežnih testova; vrati samo ono što traži pažnju
Invoke-PCHealthCheck -NoOpen -SkipNetwork -PassThru |
    Where-Object Status -in 'Warning', 'Critical'
```

| Parametar | Značenje |
|---|---|
| `-OutputPath` | Mapa za izvještaj. Zadano: `Documents\HelpdeskToolkit`. |
| `-Days` | Koliko dana Event Loga i rušenja aplikacija se analizira. Zadano: 7. |
| `-Format` | `Html` (zadano), `Json`, `Csv`, `Pdf`, `Both` (HTML i JSON) ili `All`. |
| `-SkipNetwork` | Preskače sve što pita internet: ping, DNS i HTTPS testove te traženje novijih verzija instaliranih programa. Konfiguracija adaptera se i dalje ispisuje. |
| `-ComputerName` | Provjerava drugo računalo, vidi [Drugo računalo](#drugo-računalo). |
| `-Credential` | Račun koji se koristi na drugom računalu. |
| `-NoOpen` | Ne otvara HTML izvještaj u pregledniku. |
| `-PassThru` | Dodatno vraća rezultate kao objekte. |

### U skriptama

Svaka kategorija je zasebna naredba, a `Get-PCHealthReport` vraća sve kao jedan objekt,
bez ispisa i spremanja:

```powershell
Get-HardwareHealth | Where-Object Check -like 'Disk*'
Get-NetworkHealth -SkipConnectivity
Get-ComputerSpecification | Format-Table Check, Value -AutoSize

$report = Get-PCHealthReport -Days 14
$report.Score
$report.Summary
$report.Results | Where-Object Status -eq 'Critical'

# Što računalo radi upravo sada: opterećenje po logičkom procesoru, najzaposleniji programi
$now = Get-PerformanceSnapshot
$now.Cpu.Processors | Format-Table Name, Percent, FrequencyMHz
$now.Processes

# Što je pošlo po zlu u zadnjih tjedan dana i što se prije toga promijenilo
Get-ChangeTimeline -Days 7 | Format-Table Time, Level, Kind, Title, Count -AutoSize
```

`Get-PCHealthReport` i `Invoke-PCHealthCheck` pokreću deset kategorija istovremeno,
svaku u vlastitom PowerShell runspaceu, pa provjera traje otprilike koliko njezina
najsporija kategorija, a ne koliko sve zajedno. `Get-PCHealthReport -ThrottleLimit 1`
pokreće ih jednu za drugom; tako se provjerava i drugo računalo.

Dostupne naredbe: `Invoke-PCHealthCheck`, `Show-PCHealthCheck`, `Get-PCHealthReport`,
`Compare-PCHealthReport`, `Get-SystemHealth`, `Get-ComputerSpecification`,
`Get-HardwareHealth`, `Get-SoftwareHealth`, `Get-EventLogHealth`,
`Get-WindowsUpdateHealth`, `Get-SecurityHealth`, `Get-NetworkHealth`,
`Get-PrinterHealth`, `Get-ServiceHealth`, `Get-PerformanceSnapshot`,
`Get-ChangeTimeline`. Svaka ima potpunu
pomoć: `Get-Help <naredba> -Full`.

Svaki rezultat provjere je objekt s istim svojstvima:

| Svojstvo | Sadržaj |
|---|---|
| `Category`, `Check` | Što je provjereno |
| `Description` | Što je to što se provjerava i čemu služi |
| `Status` | `OK`, `Warning`, `Critical` ili `Info` |
| `Value` | Što je pronađeno |
| `Details` | Ostatak dugog popisa (npr. svi programi koji se pokreću sa sustavom) |
| `Allowed`, `Typical` | Za mjerenja: raspon koji se smatra ispravnim i uobičajena vrijednost |
| `Recommendation` | Što učiniti kad status nije OK |

### Usporedba dviju provjera

Je li popravak pomogao? Spremi JSON izvještaj prije i poslije pa ih usporedi:

```powershell
Compare-PCHealthReport -Reference .\before.json -Difference .\after.json |
    Format-Table Change, Category, Check, Before, After
```

Svaki redak kaže je li problem nov, gori, bolji ili riješen. Rezultati koji se nisu
promijenili se ne ispisuju.

### Automatizacija: izlazni kodovi

`Invoke-HealthCheck.ps1` u glavnoj mapi pokreće provjeru i rezultat javlja izlaznim
kodom, a to je ono što gledaju sustavi za nadzor, alati za distribuciju i zakazani
zadaci:

| Izlazni kod | Značenje |
|---|---|
| 0 | Nema problema (svi rezultati su OK ili Info) |
| 1 | Barem jedan Warning, nijedan Critical |
| 2 | Barem jedan Critical |
| 3 | Sama provjera se nije mogla izvršiti |

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-HealthCheck.ps1 -Format Json -Quiet
```

### Drugo računalo

```powershell
Invoke-PCHealthCheck -ComputerName PC-014 -Credential (Get-Credential)
```

Provjera se tada izvršava na drugom računalu kroz PowerShell remoting, a izvještaj
nastaje na tvom. Na drugom računalu ne treba ništa instalirati i ništa ondje ne ostaje:
modul se pošalje i učita samo u memoriju. Uvjeti su uobičajeni za PowerShell remoting:
mora biti uključen na drugom računalu (u domeni se to inače radi kroz Group Policy), a
račun ondje mora biti administrator.

Ovaj dio je eksperimentalan. Pokriven je automatskim testovima i isproban tako da je
modul na isti način učitan u čistu sesiju na jednom računalu, ali još nije isproban
preko stvarne veze između dva računala.

## Konfiguracija

Ponašanje određuje šest podatkovnih datoteka; kod se ne mora mijenjati:

- [`HelpdeskToolkit/Config/Thresholds.psd1`](HelpdeskToolkit/Config/Thresholds.psd1):
  pragovi za Warning i Critical (npr. slobodan prostor na disku ispod 15 % i 5 %),
  odredišta mrežnih testova, popis praćenih servisa, pragovi upozorenja i statusnih
  točkica u Live monitoru, bodovi za Health score i datumi kraja podrške za verzije Windowsa (preuzeti
  s Microsoftovih stranica o životnom ciklusu; kad izađe nova verzija, dodaje se jedan
  redak).
- [`HelpdeskToolkit/Config/Descriptions.psd1`](HelpdeskToolkit/Config/Descriptions.psd1):
  objašnjenje koje se prikazuje uz svaku provjeru.
- [`HelpdeskToolkit/Config/Risks.psd1`](HelpdeskToolkit/Config/Risks.psd1):
  zašto je problem važan; prikazuje se uz svaki rezultat Warning i Critical.
- [`HelpdeskToolkit/Config/Actions.psd1`](HelpdeskToolkit/Config/Actions.psd1):
  koju stranicu Windowsa otvara gumb uz preporučeno rješenje te stranice podrške
  proizvođača računala.
- [`HelpdeskToolkit/Config/EndOfLife.psd1`](HelpdeskToolkit/Config/EndOfLife.psd1):
  programi za koje proizvođač više ne izdaje sigurnosna ažuriranja, s datumom kraja
  podrške (preuzeto sa stranica proizvođača o životnom ciklusu; kad istekne još jedna
  verzija, dodaje se jedan redak).
- [`HelpdeskToolkit/Config/Help.psd1`](HelpdeskToolkit/Config/Help.psd1):
  stranica koja objašnjava pojedini problem i adresa web pretrage za sve ostalo. U
  adresu ulazi samo naziv provjere, ili izvor i broj događaja; vrijednost rezultata
  nikad.

Vrijednosti "Typical" su iskustvene, okvirne vrijednosti za zdravo uredsko računalo.
Služe samo za usporedbu i nikad ne utječu na status.

Prijevod prozora je još jedna podatkovna datoteka:
[`HelpdeskToolkit/Lang/hr.psd1`](HelpdeskToolkit/Lang/hr.psd1) sadrži hrvatske tekstove
uz engleske izvornike. Tekst bez prijevoda jednostavno se prikaže na engleskom.

## Zahtjevi

- Windows 10 verzije 1809 ili noviji, ili Windows 11, na bilo kojem jeziku prikaza i s
  bilo kojim regionalnim postavkama. Datumi se uvijek pišu kao godina-mjesec-dan u
  kalendaru koji čita svaki program, i ondje gdje Windows godine broji drukčije
  (Saudijska Arabija, Tajland, Iran).
- Windows PowerShell 5.1 (dio Windowsa) ili PowerShell 7
- Zaslon od 1024 x 768 ili veći; prozor se sam prilagodi manjem zaslonu prijenosnika.
- PowerShell se mora smjeti izvršavati u punom obliku: na računalu na kojem ga
  organizacija ograničava (AppLocker ili App Control for Business, "Constrained
  Language Mode") alat se ne pokreće.

## Razvoj

```text
HelpdeskToolkit/          modul
  Public/                 izvezene naredbe, jedna po datoteci
  Private/                interne pomoćne funkcije, jedna po datoteci
  Config/                 pragovi, opisi, posljedice i odredišta gumba uz rješenja
  Lang/                   prijevodi prozora
  Assets/                 stilovi izvještaja, izgled prozora (XAML), tamna tema, ikona
tests/                    Pester testovi
tools/                    skripte za testiranje, slaganje izdanja i generiranje datoteka
installer/                Inno Setup skripta
docs/                     primjer izvještaja, slike, bilješke o objavi
.github/workflows/        CI i automatsko izdavanje
Invoke-HealthCheck.ps1    provjera s izlaznim kodom, za automatizaciju
Start-HelpdeskToolkit.*   pokreće prozor
```

Promjene po verzijama popisane su u [CHANGELOG.md](CHANGELOG.md).

### Testovi

Testovi koriste [Pester](https://pester.dev) 5 ili noviji s mockovima, pa rezultat ne
ovisi o računalu na kojem se izvršavaju. Stil koda provjerava
[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer).

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force

.\tools\Test-Project.ps1            # PSScriptAnalyzer i svi testovi
.\tools\Test-Project.ps1 -Coverage  # dodatno ispisuje pokrivenost koda
```

Windows PowerShell 5.1 i PowerShell 7 drže module u različitim mapama, pa ta dva modula
treba instalirati u svakoj verziji kojom želiš testirati.

GitHub Actions pokreće istu skriptu na Windows PowerShellu 5.1 i PowerShellu 7 na svaki push.

### Brzina

Što aplikaciju čini brzom i gdje gledati kad nije:

- Modul ima oko 230 datoteka s po jednom funkcijom. Čitaju se u jedan tekst i učitavaju
  kao jedan blok, što traje trećinu vremena učitavanja jedne po jedne. S varijablom
  okruženja `HELPDESKTOOLKIT_LOAD_FILES` postavljenom na `1` opet se učitavaju datoteku
  po datoteku, pa greška navodi svoju datoteku i redak; testovi rade upravo tako.
- Kategorije provjere izvršavaju se istovremeno (`Invoke-ParallelCommand`). Opterećenje
  procesora izmjeri se prije nego što krenu, da provjera ne mjeri samu sebe.
- Veličine mapa mjeri više niti koje si međusobno predaju posao
  (`Get-FolderSizeBatch`), unutar vremenskog ograničenja. Veličina koja se u tom
  vremenu nije stigla izmjeriti do kraja prikazuje se s dodatkom "ili više"
  ("12,4 GB ili više"). Petlja jedne niti poziva jednu .NET metodu po mapi i nijednu
  više: u PowerShellu 7 poziv metode iz skripte je spor i niti se za njega moraju
  izmjenjivati, pa osam niti nije bilo brže od jedne dok petlja nije tako napisana.
- Live monitor traži Windowsove klase s podacima o performansama sve odjednom
  (`Get-CimInstanceBatch`): jedno mjerenje traje oko pola sekunde umjesto dvije.

### Memorija

Što prozor drži malim, izmjereno na razvojnom računalu s Windows PowerShellom 5.1:

| | Prije | Sada |
|---|---|---|
| Prozor otvoren, prva provjera gotova | oko 470 MB | oko 215 MB |
| Nakon više ponovljenih provjera, Live monitor otvoren | 500 do 650 MB | oko 250 MB |
| Skriven pokraj sata | kao gore | 15 do 35 MB radnog skupa |

- Provjera učita desetak Windowsovih modula, a PowerShell tu memoriju ne vraća dok
  proces živi. Zato svaka provjera radi u vlastitom procesu
  (`HelpdeskToolkit\Invoke-CheckWorker.ps1`), koji završava s provjerom. Pokreće ga
  runspace prozora, koji retke što ih proces ispisuje pretvara u zapise o napretku i
  čita izvještaj koji proces ostavi kao JSON (`Invoke-WindowCheck`,
  `Receive-WindowCheck`).
- Veličine mapa koje ponovljena provjera smije ponovno upotrijebiti čuvaju se u
  datoteci u mapi aplikacije, jer procesa koji ih je izmjerio više nema
  (`Get-ProcessCache`).
- Nakon provjere, i kad se prozor sakrije, memorija koju .NET više ne koristi skuplja
  se i vraća Windowsima (`Optimize-ProcessMemory`).
- Skriven prozor odriče se runspacea Live monitora i veza kojima mjeri. Petlji se
  kaže da završi, a runspace se otpušta kad završi (`Clear-WindowWorker`).

`Write-AppLog` zapisuje što je pošlo po zlu u `app.log` u mapi aplikacije. Svaki timer
prozora sam hvata svoje greške: timer čiji rukovatelj padne Windows više nikad ne
poziva, pa bi ostao prozor koji izgleda živ, a više se ne osvježava.

### Slaganje izdanja

```powershell
.\tools\Build-Release.ps1           # instalacija (treba Inno Setup 6), ZIP i kontrolni zbrojevi u dist\
.\tools\Build-Release.ps1 -SkipInstaller
.\tools\New-TestPackage.ps1         # mapa za osobu koja isprobava: instalacija, raspakirana prijenosna kopija, upute
```

Slanje oznake poput `v1.0.0` pokreće testove, slaže instalaciju i ZIP te ih objavljuje
kao GitHub izdanje. Oznaka se mora podudarati s `ModuleVersion` u manifestu. Koraci za
izdanje, PowerShell Gallery i winget zapisani su u [docs/publishing.md](docs/publishing.md).

### Generirane datoteke

```powershell
.\tools\New-SampleReport.ps1        # docs\sample-report.html i .json (izmišljeni podaci)
.\tools\New-Screenshot.ps1          # docs\screenshot-*.png i docs\demo.gif
.\tools\New-AppIcon.ps1             # ikona aplikacije
.\tools\Test-HelpLink.ps1           # pita svaku stranicu iz Config\Help.psd1 postoji li još
```

## Privatnost i pravne napomene

- **Bez telemetrije.** Program nema poslužitelj ni korisnički račun i nikome ne šalje
  ništa o tebi ni o tvom računalu. Koje mrežne veze otvara (testovi povezanosti, winget
  i stranice koje otvoriš klikom na link) i kako se svaka izbjegava, piše u
  [PRIVACY.md](PRIVACY.md).
- **Izvještaj sadrži osobne podatke**: ime računala, korisnička imena, instalirane
  programe, mrežne adrese, serijski broj. Dijeli ga oprezno i nikad u javnoj prijavi
  problema.
- **Koristi ga samo na računalima koja su tvoja ili koja smiješ pregledavati.** To
  posebno vrijedi za `-ComputerName` i za izvještaje računala kojima se služe drugi.
- **Bez jamstva.** Alat je slobodan softver pod licencom MIT i daje se "kakav jest".
  Njegovi rezultati i prijedlozi opće su informacije, a ne stručni savjet; mogu biti
  pogrešni ili zastarjeli. Prije nego što nešto mijenjaš na računalu, napravi
  sigurnosnu kopiju.
- **Nije Microsoftov proizvod.** HelpdeskToolkit je neovisan projekt i nije povezan s
  Microsoftom niti ga Microsoft podržava. Windows i ostala imena proizvoda zaštitni su
  znakovi svojih vlasnika.

Pojedinosti su u [NOTICE.md](NOTICE.md) (na engleskom); kako se prijavljuje sigurnosni
problem piše u [SECURITY.md](SECURITY.md), a na što paziti pri doprinosu u
[CONTRIBUTING.md](CONTRIBUTING.md).

## Licenca

[MIT](LICENSE). Copyright (c) 2026 Antonio Majstorovic.
