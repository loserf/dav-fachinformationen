# DAV Fachinformationen — Übersicht

Eine durchsuchbare, nach Themen geordnete Übersicht aus drei Quellen rund um die
[Deutsche Aktuarvereinigung e.V. (DAV)](https://aktuar.de/de/wissen/fachinformationen/):

- **aktuar.de**: Ergebnisberichte, Hinweise, Richtlinien, Use Cases
- **[github.com/DeutscheAktuarvereinigung](https://github.com/DeutscheAktuarvereinigung)**: GitHub-Material,
  Best Notebook Award, Data Science Challenge
- **[actuview.com](https://actuview.com/)**: Vorträge des DAV/DGVFM Annual Meeting und Autumn Meeting ab 2020
  (Titel, Autor:innen, Tagung, Fachgruppe, PDF-Folien-Verfügbarkeit)

Kein offizielles DAV-Angebot — ein privates Hilfsmittel, das ausschließlich öffentlich zugängliche
Schnittstellen ausliest und daraus eine schnell durchsuchbare Seite baut.

📋 [Entwicklungsprotokoll](docs/entwicklungsprotokoll.html) — wie dieses Projekt Schritt für Schritt
mit Claude Code entstanden ist, inkl. Token-/Kostenauswertung der Entwicklungssitzung.

## Wie es funktioniert

```
scripts/update-data.ps1   →   data/data.json   →   index.html (liest data.json per fetch)
```

- **`scripts/update-data.ps1`** fragt nacheinander die öffentliche Solr-Suche von aktuar.de, die
  öffentliche GitHub-REST-API der Organisation und die öffentliche Video-API von actuview.com ab,
  säubert die Rohdaten (HTML-Tags entfernen, Kurzbeschreibung extrahieren, verantwortliches Gremium
  wo möglich erkennen, doppelte Fassungen desselben Dokuments zusammenführen, GitHub-Material mit
  passenden Fachinformationen querverlinken) und schreibt das Ergebnis nach `data/data.json`.
- **`index.html`** ist eine einzelne statische Seite ohne Build-Schritt. Sie lädt `data/data.json`
  per `fetch` und rendert Filter, Suche (auch nach actuview-Sprecher:innen, die häufig zugleich
  DAV-Arbeitsgruppenmitglieder sind) und die nach Themen gruppierte Liste im Browser.
  Das „Neu“-Abzeichen (≤ 4 Monate) wird beim Aufruf clientseitig aus dem aktuellen Datum berechnet,
  muss also nicht bei jedem Lauf neu erzeugt werden.

## Lokal ausprobieren

```bash
pwsh scripts/update-data.ps1      # Daten aktualisieren (braucht Internetzugang)
python -m http.server 8000        # index.html braucht einen echten HTTP-Server (kein file://)
```
Danach `http://localhost:8000/index.html` öffnen.

## Kostenlos veröffentlichen (GitHub Pages)

1. Ein neues **öffentliches** GitHub-Repository anlegen und diesen Ordner hineinschieben:
   ```bash
   git init
   git add .
   git commit -m "Erstveröffentlichung"
   git branch -M main
   git remote add origin https://github.com/<dein-user>/<dein-repo>.git
   git push -u origin main
   ```
2. Im Repo unter **Settings → Pages** als Quelle **„GitHub Actions“** auswählen.
3. Fertig — die Seite ist danach unter `https://<dein-user>.github.io/<dein-repo>/` erreichbar,
   dauerhaft kostenlos (GitHub Pages ist für öffentliche Repos gratis).

## Aktuell halten

Die Workflow-Datei **`.github/workflows/update-data.yml`** läuft automatisch **jeden Montagmorgen**
(per `cron`), holt neue/aktualisierte Fachinformationen, committet `data/data.json` bei Änderungen
und deployt die Seite neu. Kein manueller Aufwand nötig.

- Häufigkeit ändern: die `cron`-Zeile in der Workflow-Datei anpassen
  ([crontab.guru](https://crontab.guru) hilft bei der Syntax).
- Manuell anstoßen: im Reiter **Actions** des Repos den Workflow „DAV-Fachinformationen
  aktualisieren“ auswählen und **„Run workflow“** klicken.
- „Neu“-Schwelle ändern: `NEW_DAYS` in `index.html` (Standard: 122 Tage ≈ 4 Monate).

## Rechtliches / Umgang mit Mitgliederinhalten

- Alle Inhalte und Rechte liegen bei der Deutschen Aktuarvereinigung e.V. Diese Seite reproduziert
  keine Volltexte, sondern nur Titel, Datum, Thema, Schlagworte und einen kurzen (≤ 3 Sätze)
  automatisiert extrahierten Auszug aus dem öffentlichen „Überblick“-Absatz, jeweils mit Link zur
  Originalquelle.
- Als **„🔒 Mitglieder“** markierte Dokumente sind auf aktuar.de nur mit DAV-Login vollständig
  abrufbar. Für diese verlinkt die Seite bewusst nur auf die allgemeine Fachinformationen-Suche
  statt auf eine (anonym nicht auflösbare) Detailseite.
- actuview-Vorträge und deren PDF-Folien erfordern zum Ansehen ein (kostenloses) actuview-Konto;
  diese Seite übernimmt keine Videos oder PDFs, sondern nur Metadaten und einen Link dorthin.
- Die Suche nach „Vortragenden“ erfolgt über actuview-Sprecher:innen, nicht über eine offizielle
  DAV-Mitgliederliste — viele Vortragende sind Mitglieder der jeweiligen Arbeitsgruppe/des
  Ausschusses, aber nicht zwingend alle.
- Die Kurzbeschreibungen sind automatisiert erzeugt und können ungenau sein — im Zweifel gilt immer
  das Originaldokument/-video.

## Struktur

```
index.html                        Statische Seite (Suche, Filter, Themen-Gruppierung)
data/data.json                    Aufbereiteter Datenbestand (wird automatisch aktualisiert)
scripts/update-data.ps1           Abruf- und Aufbereitungsskript (PowerShell 7 / pwsh)
.github/workflows/update-data.yml Wöchentlicher Auto-Update- und Deploy-Workflow
```
