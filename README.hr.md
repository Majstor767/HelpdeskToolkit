# HelpdeskToolkit

[![CI](https://github.com/Majstor767/HelpdeskToolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/Majstor767/HelpdeskToolkit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![PowerShell 5.1 | 7](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE)

*English version: [README.md](README.md)*

Dijagnostički alat za Windows računala, namijenjen radu u helpdesku i IT podršci. Jednim
klikom ili jednom naredbom provjeri stanje računala i napravi pregledan izvještaj s
pronađenim problemima i preporukama što učiniti.

- **Samo čita.** Alat samo čita podatke i nikad ništa ne mijenja na sustavu.
- **Ne traži administratorska prava.** Provjere kojima trebaju preskače i označava s "Requires admin".
- **Ne traži ništa osim samog alata.** Napisan je u PowerShellu i koristi ono što Windows već ima.

Sučelje i izvještaj su na engleskom jeziku.

![Prozor aplikacije](docs/screenshot-window.png)

## Što provjerava

| Kategorija | Provjere |
|---|---|
| System | Ime računala, verzija i build Windowsa, ima li ta verzija još Microsoftovu podršku, datum instalacije, proizvođač i model, domena ili radna grupa, prijavljeni korisnik, vremenska zona, uptime, indeks stabilnosti, aktivacija Windowsa, programi koji se pokreću sa sustavom |
| Specifications | Procesor, memorijski moduli i slobodni utori, grafičke kartice, matična ploča, BIOS/UEFI, serijski broj |
| Hardware | Opterećenje CPU-a, zauzeće RAM-a i najveći potrošači memorije, zdravlje svakog fizičkog diska, slobodan prostor po disku, prostor koji se može osloboditi (privremene datoteke, Downloads, koš za smeće), page file, uređaji bez ispravnog drivera, baterija |
| Software | Instalirani programi s verzijama, nedavno instalirani programi, rušenja aplikacija po programu, zadani preglednik |
| Event Log | Neočekivana gašenja, plavi ekrani, kritični događaji i greške u System i Application logu u zadnjih N dana, najčešći izvori |
| Windows Update | Zadnje instalirano ažuriranje, čeka li se restart, jesu li ažuriranja pauzirana |
| Security | Zaštita u stvarnom vremenu, starost definicija, zaštita od neovlaštenih izmjena i zadnje skeniranje Microsoft Defendera, firewall profili, User Account Control, Remote Desktop, vrsta računa, lokalni računi i račun Guest, dijeljene mape, Secure Boot, TPM\*, BitLocker\* |
| Network | Adapteri (IPv4, gateway, DNS, DHCP, MAC, brzina veze), mrežni profil, proxy, hosts datoteka, mapirani mrežni diskovi, ping gatewaya i interneta, DNS razlučivanje, HTTPS pristup, točnost sata |
| Printers | Zadani pisač, instalirani pisači i oni koji su offline, dokumenti zaglavljeni u redu za ispis |
| Services | DHCP Client, DNS Client, Windows Event Log, Workstation, Windows Defender Firewall, Microsoft Defender Antivirus, Windows Update, BITS, Print Spooler |

\* traži administratorska prava; inače je označeno s "Requires admin".

Svaki rezultat ima status (**OK**, **Warning**, **Critical** ili **Info**), kratko
objašnjenje što je to što se provjerava i preporučeno rješenje kad god je status Warning
ili Critical. Uz mjerenja se prikazuju i dopušteni raspon te tipična vrijednost za
usporedbu.

## Izvještaj

HTML izvještaj je jedna samostalna datoteka (bez skripti, ništa se ne učitava s
interneta), pa se može poslati e-mailom ili priložiti uz ticket. Prati svijetlu ili
tamnu temu sustava i ima izgled prilagođen ispisu.

![HTML izvještaj](docs/screenshot-report.png)

Cijeli primjer s izmišljenim podacima nalazi se u [docs/sample-report.html](docs/sample-report.html)
(preuzmi ga i otvori u pregledniku). Isti podaci u JSON-u:
[docs/sample-report.json](docs/sample-report.json).

## Instalacija

### Instalacijski program (preporučeno)

1. Preuzmi `HelpdeskToolkit-Setup-<verzija>.exe` sa stranice [Releases](https://github.com/Majstor767/HelpdeskToolkit/releases).
2. Pokreni ga. Instalira se samo za trenutnog korisnika i ne traži administratorska prava.
3. Pokreni **HelpdeskToolkit** iz Start izbornika.

Instalacijski program nije digitalno potpisan, pa Windows SmartScreen pri prvom
pokretanju prikaže "Windows protected your PC". Odaberi **More info** pa **Run anyway**.
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

## Korištenje

### Prozor

```powershell
Show-PCHealthCheck
```

Klikni **Run check**. Stranica **Overview** prikazuje sve probleme s preporučenim
rješenjem. Odaberi kategoriju lijevo (System, Hardware, Network, ...) da vidiš sve što je
u njoj provjereno; točka i broj uz svaku kategoriju pokazuju gdje su problemi.
**Open HTML report** sprema izvještaj i otvara ga u pregledniku, a **Save as...** ga
sprema kao HTML ili JSON na mjesto koje odabereš.

### Naredbeni redak

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
| `-Format` | `Html` (zadano), `Json` ili `Both`. |
| `-SkipNetwork` | Preskače ping, DNS i HTTPS testove. Konfiguracija adaptera se i dalje ispisuje. |
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
$report.Summary
$report.Results | Where-Object Status -eq 'Critical'
```

Dostupne naredbe: `Invoke-PCHealthCheck`, `Show-PCHealthCheck`, `Get-PCHealthReport`,
`Get-SystemHealth`, `Get-ComputerSpecification`, `Get-HardwareHealth`,
`Get-SoftwareHealth`, `Get-EventLogHealth`, `Get-WindowsUpdateHealth`,
`Get-SecurityHealth`, `Get-NetworkHealth`, `Get-PrinterHealth`, `Get-ServiceHealth`. Svaka ima potpunu pomoć: `Get-Help <naredba> -Full`.

Svaki rezultat je objekt s istim svojstvima:

| Svojstvo | Sadržaj |
|---|---|
| `Category`, `Check` | Što je provjereno |
| `Description` | Što je to što se provjerava i čemu služi |
| `Status` | `OK`, `Warning`, `Critical` ili `Info` |
| `Value` | Što je pronađeno |
| `Details` | Ostatak dugog popisa (npr. svi programi koji se pokreću sa sustavom) |
| `Allowed`, `Typical` | Za mjerenja: raspon koji se smatra ispravnim i uobičajena vrijednost |
| `Recommendation` | Što učiniti kad status nije OK |

## Konfiguracija

Ponašanje određuju dvije podatkovne datoteke; kod se ne mora mijenjati:

- [`HelpdeskToolkit/Config/Thresholds.psd1`](HelpdeskToolkit/Config/Thresholds.psd1):
  pragovi za Warning i Critical (npr. slobodan prostor na disku ispod 15 % i 5 %),
  odredišta mrežnih testova, popis praćenih servisa i datumi kraja podrške za verzije
  Windowsa (preuzeti s Microsoftovih stranica o životnom ciklusu; kad izađe nova
  verzija, dodaje se jedan redak).
- [`HelpdeskToolkit/Config/Descriptions.psd1`](HelpdeskToolkit/Config/Descriptions.psd1):
  objašnjenje koje se prikazuje uz svaku provjeru.

Vrijednosti "Typical" su iskustvene, okvirne vrijednosti za zdravo uredsko računalo.
Služe samo za usporedbu i nikad ne utječu na status.

## Zahtjevi

- Windows 10 verzije 1809 ili noviji, ili Windows 11
- Windows PowerShell 5.1 (dio Windowsa) ili PowerShell 7

## Razvoj

```text
HelpdeskToolkit/          modul
  Public/                 izvezene naredbe, jedna po datoteci
  Private/                interne pomoćne funkcije, jedna po datoteci
  Config/                 pragovi i opisi
  Assets/                 stilovi izvještaja, izgled prozora (XAML), ikona
tests/                    Pester testovi
tools/                    skripte za testiranje, slaganje izdanja i generiranje datoteka
installer/                Inno Setup skripta
docs/                     primjer izvještaja i slike
.github/workflows/        CI i automatsko izdavanje
```

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

GitHub Actions pokreće istu skriptu na Windows PowerShellu 5.1 i PowerShellu 7 na svaki push.

### Slaganje izdanja

```powershell
.\tools\Build-Release.ps1           # instalacija (treba Inno Setup 6), ZIP i kontrolni zbrojevi u dist\
.\tools\Build-Release.ps1 -SkipInstaller
```

Slanje oznake poput `v1.0.0` pokreće testove, slaže instalaciju i ZIP te ih objavljuje
kao GitHub izdanje. Oznaka se mora podudarati s `ModuleVersion` u manifestu.

### Generirane datoteke

```powershell
.\tools\New-SampleReport.ps1        # docs\sample-report.html i .json (izmišljeni podaci)
.\tools\New-Screenshot.ps1          # docs\screenshot-*.png
.\tools\New-AppIcon.ps1             # ikona aplikacije
```

## Licenca

[MIT](LICENSE)
