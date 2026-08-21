# Aktualisiert data/data.json mit Inhalten aus drei Quellen:
#  1. aktuar.de       -> Ergebnisbericht, Hinweis, Richtlinie, Use Case
#  2. GitHub-Org       -> GitHub-Material, Best Notebook Award, Data Science Challenge
#     (github.com/DeutscheAktuarvereinigung, oeffentliche REST-API, kein Token noetig)
#  3. actuview.com     -> Art "actuview" (Vortraege des DAV/DGVFM Annual/Autumn Meeting ab 2020)
#
# Kein Login noetig fuer Titel/Datum/Thema/Kurzbeschreibung; Mitgliederinhalte bzw.
# login-pflichtige Videos bleiben verlinkt, aber nicht im Volltext uebernommen.
#
# Aufruf:  pwsh scripts/update-data.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$headers = @{ "User-Agent" = "Mozilla/5.0 (compatible; DAV-Fachinfo-Uebersicht/1.0; +https://github.com/)" }

function Parse-DavDate($s) {
    try { return [datetime]::ParseExact($s, "dd.MM.yyyy", $null) } catch { return $null }
}

$AbbrevFrom = @("u.a.","z.B.","bzw.","ggf.","d.h.","i.d.R.","u.U.","u.Ä.","Nr.","Nrn.","Abs.","Art.","Ziff.","Buchst.","vgl.","Vgl.","S.","Abb.","Tab.","bspw.")
$AbbrevTo   = @("u#a#","z#B#","bzw#","ggf#","d#h#","i#d#R#","u#U#","u#AE#","Nr#","Nrn#","Abs#","Art#","Ziff#","Buchst#","vgl#","Vgl#","S#","Abb#","Tab#","bspw#")
function Protect-Abbrev($text) {
    for ($i = 0; $i -lt $AbbrevFrom.Length; $i++) { $text = $text.Replace($AbbrevFrom[$i], $AbbrevTo[$i]) }
    return $text
}
function Restore-Abbrev($text) {
    for ($i = 0; $i -lt $AbbrevFrom.Length; $i++) { $text = $text.Replace($AbbrevTo[$i], $AbbrevFrom[$i]) }
    return $text
}
function Strip-Html($s) {
    if (-not $s) { return "" }
    $s = $s -replace "&lt;", "<" -replace "&gt;", ">"
    $s = [regex]::Replace($s, "<[^>]+>", " ")
    $s = $s -replace "&nbsp;", " " -replace "&amp;", "&" -replace "&quot;", '"' -replace "&#39;", "'"
    $s = [regex]::Replace($s, "\s+", " ")
    return $s.Trim()
}
function Get-ShortText($text, $maxSentences, $maxLen) {
    if (-not $text) { return "" }
    $protectedText = Protect-Abbrev $text
    $sentences = [regex]::Matches($protectedText, "[^.!?]+[.!?]+") | ForEach-Object { Restore-Abbrev $_.Value.Trim() }
    if ($sentences.Count -eq 0) { return $text }
    $out = ""; $count = 0
    foreach ($sen in $sentences) {
        if ($count -ge $maxSentences -or ($out.Length + $sen.Length) -gt $maxLen) { break }
        $out += " " + $sen; $count++
    }
    $out = $out.Trim()
    if (-not $out) { $out = $text.Substring(0, [Math]::Min($maxLen, $text.Length)) + "…" }
    return $out
}

# Theme-Umbenennungen (z.B. Punkt 4 der Erweiterung: ADS -> ADS / AI)
$ThemeRename = @{ "Actuarial Data Science" = "Actuarial Data Science / AI" }
function Rename-Theme($t) { if ($ThemeRename.ContainsKey($t)) { return $ThemeRename[$t] } else { return $t } }

# ============================================================================
# QUELLE 1: aktuar.de Fachinformationen
# ============================================================================
Write-Host "== Quelle 1/3: aktuar.de Fachinformationen =="
$favTypes = @("Ergebnisbericht", "Hinweis", "Richtlinie", "Use Case")
$raw = New-Object System.Collections.Generic.List[object]

function Get-Committee($content) {
    $text = Strip-Html $content
    $patterns = @(
        'durch (?:den|die|das) (.{3,90}?) am \d{1,2}\.',
        '(Arbeitsgruppe [^\.,;]{3,90})',
        '(Unterarbeitsgruppe [^\.,;]{3,90})',
        '(Ausschuss(?:es)? [^\.,;]{3,90})',
        '(Vorstandsausschuss[^\.,;]{0,90})',
        '(Vorstand der DAV)'
    )
    foreach ($p in $patterns) {
        $m = [regex]::Match($text, $p)
        if ($m.Success) {
            $val = ($m.Groups[1].Value.Trim() -replace "\s+", " ")
            if ($val.Length -gt 3 -and $val.Length -lt 100) { return $val }
        }
    }
    return ""
}

foreach ($type in $favTypes) {
    $page = 1
    $encType = [System.Uri]::EscapeDataString($type)
    do {
        $url = "https://aktuar.de/de/wissen/fachinformationen?type=7383&tx_solr%5Bq%5D=*&tx_solr%5Bpage%5D=$page&tx_solr%5Bfilter%5D%5B0%5D=filter_categories%3A$encType&tx_solr%5Bfilter%5D%5B1%5D=type%3A30"
        $resp = Invoke-WebRequest -Uri $url -Headers $headers
        [xml]$xml = $resp.Content

        $totalCount = 0
        foreach ($facet in $xml.root.facets.facet) {
            if ($facet.name -eq "filter_categories") {
                foreach ($opt in $facet.options.option) {
                    if ($opt.label -eq $type) { $totalCount = [int]$opt.count }
                }
            }
        }

        $results = $xml.root.results.result
        if ($null -eq $results) { $results = @() }
        if ($results -isnot [System.Array]) { $results = @($results) }

        foreach ($r in $results) {
            $tagList = @()
            if ($r.tags -and $r.tags.tag) { $tagList = @(@($r.tags.tag)) }
            $raw.Add([PSCustomObject]@{
                artType     = $type
                title       = ($r.title -as [string]).Trim()
                publishedAt = ($r.publishedAt -as [string]).Trim()
                url         = ($r.url -as [string]).Trim()
                category    = ($r.category -as [string]).Trim()
                tags        = $tagList
                teaser      = ($r.teaser.InnerText -as [string])
                content     = ($r.content -as [string])
                specType    = ($r.specialisedInformationType -as [string])
                locked      = ($r.locked -as [string])
            })
        }
        Write-Host "  $type Seite $page : $($results.Count) Treffer (gesamt: $totalCount)"
        $page++
    } while (($page - 1) * 10 -lt $totalCount)
}

foreach ($item in $raw) {
    Add-Member -InputObject $item -NotePropertyName "parsedDate" -NotePropertyValue (Parse-DavDate $item.publishedAt) -Force
}

$fachinfoItems = New-Object System.Collections.Generic.List[object]
foreach ($g in ($raw | Group-Object title)) {
    $items = $g.Group | Sort-Object url, publishedAt -Unique | Sort-Object parsedDate -Descending
    $primary = $items | Where-Object { $_.url -like "*/detail/*" } | Select-Object -First 1
    if (-not $primary) { $primary = $items | Select-Object -First 1 }

    $prevVersions = @()
    foreach ($o in ($items | Where-Object { $_.url -ne $primary.url -or $_.publishedAt -ne $primary.publishedAt })) {
        if ($o.url -like "*/detail/*") { $prevVersions += [PSCustomObject]@{ date = $o.publishedAt; url = $o.url } }
    }

    $allTypesForUrl = ($raw | Where-Object { $_.url -eq $primary.url -and $_.publishedAt -eq $primary.publishedAt } | Select-Object -ExpandProperty artType -Unique)
    $hasDirectLink = $primary.url -like "*/detail/*"
    $iso = ""
    if ($primary.parsedDate) { $iso = $primary.parsedDate.ToString("yyyy-MM-dd") }

    $descText = Strip-Html $primary.content
    if (-not $descText) { $descText = Strip-Html $primary.teaser }
    $descText = $descText -replace "^Überblick\s*", ""

    $fachinfoItems.Add([PSCustomObject]@{
        type             = ($allTypesForUrl -join " / ")
        title            = ($primary.title -replace "\s+", " ").Trim()
        date             = $primary.publishedAt
        dateIso          = $iso
        theme            = Rename-Theme $primary.category
        tags             = $primary.tags
        committee        = Get-Committee $primary.content
        description      = Get-ShortText $descText 3 420
        url              = $(if ($hasDirectLink) { $primary.url } else { "https://aktuar.de/de/wissen/fachinformationen/" })
        hasDirectLink    = $hasDirectLink
        locked           = ($primary.locked -eq "true")
        isPdf            = ($primary.specType -eq "download")
        previousVersions = $prevVersions
    })
}
Write-Host "  -> $($fachinfoItems.Count) eindeutige Fachinformationen"

# ============================================================================
# QUELLE 2: GitHub-Org github.com/DeutscheAktuarvereinigung
# ============================================================================
Write-Host ""
Write-Host "== Quelle 2/3: GitHub github.com/DeutscheAktuarvereinigung =="

$githubItems = New-Object System.Collections.Generic.List[object]
$crossRef = @{}
try {
    $ghHeaders = @{ "User-Agent" = "DAV-Fachinfo-Uebersicht"; "Accept" = "application/vnd.github+json" }
    $repos = New-Object System.Collections.Generic.List[object]
    $ghPage = 1
    do {
        $r = Invoke-RestMethod -Uri "https://api.github.com/orgs/DeutscheAktuarvereinigung/repos?per_page=100&page=$ghPage" -Headers $ghHeaders
        foreach ($x in $r) { $repos.Add($x) }
        $ghPage++
    } while ($r.Count -eq 100)
    Write-Host "  $($repos.Count) Repositories gefunden"

    # Handkuratierte, lesbare Titel fuer bekannte Repos. Unbekannte (neue) Repos
    # bekommen automatisch einen aus dem Namen abgeleiteten Titel.
    $titleMap = @{
        "ADS_Use_Cases" = "ADS Use Cases (Notebook-Sammlung)"
        "claim_frequency" = "Claim Frequency: GLM, Neural Network & Gradient Boosting für die Schadentarifierung"
        "Deriving-NHANES-data-set-CDC-for-mortality-analysis" = "Aufbereitung des NHANES-Datensatzes (CDC) für Mortalitätsanalysen"
        "GenAI_Beyond_the_Basics" = "GenAI Beyond the Basics"
        "Impact_of_the_COVID-19_Pandemic" = "Impact of the COVID-19 Pandemic: Modeling and Forecasting"
        "insurance_scr_data" = "Insurance SCR Data: interne Modelldaten für drei Portfolios"
        "Mortality_Modeling" = "Multi-Population Mortality Modeling With Neural Networks"
        "portxlpy" = "portxlpy: Portierung Excel-Referenzrechner nach Python"
        "Python_fuer_Aktuare" = "Python für Aktuare (DAA-Fortbildung, Notebooks)"
        "Use-Case-zur-Modellierung-von-Cyberrisiken" = "Use Case zur Modellierung von Cyberrisiken (Notebooks)"
        "WorkingGroup_AI_ModernMethods_Health" = "Arbeitsgruppe KI & moderne Methoden in der Krankenversicherung"
        "WorkingGroup_Anonymization_Pseudonymization" = "Arbeitsgruppe Anonymisierung & Pseudonymisierung"
        "WorkingGroup_Bias_Discrimination_Notebooks" = "Arbeitsgruppe Bias & Diskriminierung in Modellen"
        "WorkingGroup_eXplainableAI_Notebooks" = "Arbeitsgruppe eXplainable AI"
        "WorkingGroup_Synthetic_Data" = "Arbeitsgruppe Synthetische Daten"
        "Data_Science_Challenge_2020_Berufsunfaehigkeit" = "Data Science Challenge 2020 – Machine-Learning-Methoden für die Berufsunfähigkeitsversicherung"
        "Data_Science_Challenge_2020_Betrugserkennung" = "Data Science Challenge 2020 – Betrugserkennung (Fraud Detection)"
        "Data-Science-Challenge2021_Explainable-Machine-Learning" = "Data Science Challenge 2021 – Explainable Machine Learning"
        "Data_Science_Challenge_2022_Python-Notebook_zur_Erstellung_von_Schadenhaeufigkeitsmodellen" = "Data Science Challenge 2022 – Schadenhäufigkeitsmodelle in Python"
    }
    # Repo-Name -> Titel einer bestehenden Fachinformation (fuer Cross-Referenz)
    $crossRefMap = @{
        "claim_frequency" = "Schadenhäufigkeitsmodellierung in der Schadentarifierung mit GLM, Deep Learning und Gradient Boosting"
        "Mortality_Modeling" = "Neuronale Netze treffen auf Mortalitätsprognose"
        "insurance_scr_data" = "Use (this Solvency II) case! Neuronale Netze treffen auf Least Squares Monte Carlo"
        "Use-Case-zur-Modellierung-von-Cyberrisiken" = "UseCase zur Modellierung von Cyberrisiken"
    }

    foreach ($r in $repos) {
        if ($r.name -eq ".github") { continue }
        if ($r.fork) { continue }
        if ($r.archived) { continue }

        $art = "GitHub-Material"
        $extraTags = @()
        $title = $null

        if ($r.name -match '^(\d{4})_CADS_(Immersion|Completion)_Best_Notebooks$') {
            $art = "Best Notebook Award"
            $year = $Matches[1]; $kind = $Matches[2]
            $title = "Best Notebook Award – CADS $kind $year"
            $extraTags = @("CADS $kind", $year)
        }
        elseif ($r.name -match 'Data.Science.Challenge') {
            $art = "Data Science Challenge"
            $yearMatch = [regex]::Match($r.name, '\d{4}')
            $year = if ($yearMatch.Success) { $yearMatch.Value } else { "" }
            if ($titleMap.ContainsKey($r.name)) { $title = $titleMap[$r.name] }
            else {
                $rest = ($r.name -replace 'Data[_-]Science[_-]Challenge2?_?\d{4}_?', '') -replace "_"," " -replace "-"," "
                $title = "Data Science Challenge $year – $rest".Trim()
            }
            $extraTags = @($year)
        }
        else {
            if ($titleMap.ContainsKey($r.name)) { $title = $titleMap[$r.name] }
            else { $title = ($r.name -replace "_"," " -replace "-"," ") }
        }

        $desc = $r.description
        if ([string]::IsNullOrWhiteSpace($desc)) { $desc = "Notebooks / Materialien der DAV-Arbeitsgruppe Actuarial Data Science auf GitHub." }

        $pushed = [datetime]$r.pushed_at
        $topics = @()
        if ($r.topics) { $topics = @(@($r.topics)) }
        $tags = @(@($topics + $extraTags) | Where-Object { $_ } | Select-Object -Unique)

        $githubItems.Add([PSCustomObject]@{
            type             = $art
            title            = $title
            date             = $pushed.ToString("dd.MM.yyyy")
            dateIso          = $pushed.ToString("yyyy-MM-dd")
            theme            = "Actuarial Data Science / AI"
            tags             = $tags
            committee        = ""
            description      = $desc
            url              = $r.html_url
            hasDirectLink    = $true
            locked           = $false
            isPdf            = $false
            previousVersions = @()
        })

        if ($crossRefMap.ContainsKey($r.name)) {
            $crossRef[$crossRefMap[$r.name]] = $r.html_url
        }
    }
    Write-Host "  -> $($githubItems.Count) GitHub-Eintraege ($(($githubItems | Where-Object {$_.type -eq 'Best Notebook Award'}).Count) Best Notebook Award, $(($githubItems | Where-Object {$_.type -eq 'Data Science Challenge'}).Count) Data Science Challenge)"
}
catch {
    Write-Warning "GitHub-Abruf fehlgeschlagen, wird uebersprungen: $_"
}

# Cross-Referenzen in bestehende Fachinformationen eintragen (Art-Filter "GitHub-Material" greift dann auch dort)
foreach ($fi in $fachinfoItems) {
    if ($crossRef.ContainsKey($fi.title)) {
        $fi.type = $fi.type + " / GitHub-Material"
        Add-Member -InputObject $fi -NotePropertyName "githubUrl" -NotePropertyValue $crossRef[$fi.title] -Force
    }
}

# ============================================================================
# QUELLE 3: actuview.com (DAV/DGVFM Annual & Autumn Meeting Vortraege ab 2020)
# ============================================================================
Write-Host ""
Write-Host "== Quelle 3/3: actuview.com Vortraege =="

$actuviewItems = New-Object System.Collections.Generic.List[object]
try {
    $avHeaders = @{ "User-Agent" = "Mozilla/5.0 (compatible; DAV-Fachinfo-Uebersicht/1.0)" }
    $eventsResp = Invoke-WebRequest -Uri "https://actuview.com/api/events" -Headers $avHeaders
    $events = $eventsResp.Content | ConvertFrom-Json

    $relevantEvents = $events | Where-Object {
        $_.title -match '^DAV/DGVFM (Annual Meeting|Autumn Meeting|e-Jahrestagung)' -and
        [datetime]$_.date -ge [datetime]"2020-01-01" -and
        $_.media_count -gt 0
    }
    Write-Host "  $($relevantEvents.Count) relevante Events (Annual/Autumn Meeting ab 2020)"

    $stubs = New-Object System.Collections.Generic.List[object]
    foreach ($ev in $relevantEvents) {
        $limit = [Math]::Max(50, $ev.media_count + 5)
        $url = "https://actuview.com/api/videos?orderby=published&sortdirection=desc&limit=$limit&filterbyevent=$($ev.event_id)&filterbylanguage=cs,de,en,es,fr,ga,it,lt,pt"
        $resp = Invoke-WebRequest -Uri $url -Headers $avHeaders
        $data = $resp.Content | ConvertFrom-Json
        $medium = $data.media.medium
        if ($null -eq $medium) { $medium = @() }
        if ($medium -isnot [System.Array]) { $medium = @($medium) }
        foreach ($m in $medium) {
            $stubs.Add([PSCustomObject]@{
                mid = $m.mid; title = $m.title; description = $m.description
                eventId = $ev.event_id; eventTitle = $ev.title; eventDate = $ev.date
            })
        }
        Write-Host "    Event $($ev.event_id) ($($ev.title)): $($medium.Count) Videos"
    }
    Write-Host "  -> $($stubs.Count) Vortraege gesamt, lade Details (parallel)..."

    $details = $stubs | ForEach-Object -ThrottleLimit 12 -Parallel {
        $mid = $_.mid
        $h = @{ "User-Agent" = "Mozilla/5.0 (compatible; DAV-Fachinfo-Uebersicht/1.0)" }
        try {
            $vResp = Invoke-WebRequest -Uri "https://actuview.com/api/videos/$mid" -Headers $h -TimeoutSec 20
            $v = ($vResp.Content | ConvertFrom-Json).medium
        } catch { $v = $null }
        try {
            $sResp = Invoke-WebRequest -Uri "https://actuview.com/api/speakers/byMedium/$mid" -Headers $h -TimeoutSec 20
            $sData = $sResp.Content | ConvertFrom-Json
            $sp = @()
            if ($sData.speaker) {
                $sArr = @($sData.speaker)
                $sp = @($sArr | ForEach-Object { $_.title })
            }
        } catch { $sp = @() }

        $catNames = @()
        $hasAtt = $false
        if ($v -and $v.categories -and $v.categories.category) {
            $cats = @($v.categories.category)
            $catNames = @($cats | ForEach-Object { $_.name })
        }
        if ($v -and $v.media_attachments -and $v.media_attachments.attachment) { $hasAtt = $true }

        [PSCustomObject]@{ mid = $mid; categories = $catNames; speakers = $sp; hasAttachment = $hasAtt; slug = $v.slug }
    } -AsJob | Wait-Job | Receive-Job

    $detailsByMid = @{}
    foreach ($d in $details) { $detailsByMid[[string]$d.mid] = $d }

    $themeMapAv = @{
        "DATA SCIENCE / AI" = "Actuarial Data Science / AI"; "ASTIN / NON-LIFE" = "Schadenversicherung"
        "LIFE" = "Lebensversicherung"; "HEALTH" = "Krankenversicherung"; "AFIR / ERM / RISK" = "Risikomanagement"
        "PENSIONS" = "betriebliche Altersversorgung"; "BANKING / FINANCE" = "Investment"
        "IACA / CONSULTING" = "Berufsständisches"; "DIVERSITY & INCLUSION" = "Berufsständisches"
        "EDUCATION" = "Berufsständisches"; "PROFESSIONALISM" = "Berufsständisches"
        "THOUGHT LEADERSHIP" = "Fachinformationen"; "MISC" = "Fachinformationen"
    }

    foreach ($s in $stubs) {
        $d = $detailsByMid[[string]$s.mid]
        $cats = @(if ($d -and $d.categories) { @($d.categories) } else { @() })
        $category = ($cats -join ", ")
        $primaryCat = ""
        if ($cats.Count -gt 0) { $primaryCat = ([string]$cats[0]).ToUpper().Trim() }
        $theme = if ($primaryCat -and $themeMapAv.ContainsKey($primaryCat)) { $themeMapAv[$primaryCat] } else { "Fachinformationen" }
        $speakers = @(if ($d -and $d.speakers) { @($d.speakers) } else { @() })
        $hasPdf = if ($d) { [bool]$d.hasAttachment } else { $false }
        $slug = if ($d -and $d.slug) { $d.slug } else { "" }
        $videoUrl = if ($slug) { "https://actuview.com/videos/$slug-$($s.mid)" } else { "https://actuview.com/videos/$($s.mid)" }

        $desc = Get-ShortText (Strip-Html $s.description) 3 380

        $actuviewItems.Add([PSCustomObject]@{
            type             = "actuview"
            title            = ($s.title -replace "\s+", " ").Trim()
            date             = ([datetime]$s.eventDate).ToString("dd.MM.yyyy")
            dateIso          = ([datetime]$s.eventDate).ToString("yyyy-MM-dd")
            theme            = $theme
            tags             = @()
            committee        = $category
            authors          = $speakers
            event            = $s.eventTitle
            pdfAvailable     = $hasPdf
            description      = $desc
            url              = $videoUrl
            hasDirectLink    = $true
            locked           = $false
            isPdf            = $false
            previousVersions = @()
        })
    }
    Write-Host "  -> $($actuviewItems.Count) actuview-Eintraege ($((($actuviewItems | Where-Object {$_.pdfAvailable}).Count)) mit PDF-Folien)"
}
catch {
    Write-Warning "actuview-Abruf fehlgeschlagen, wird uebersprungen: $_"
}

# ============================================================================
# ZUSAMMENFUEHREN & SCHREIBEN
# ============================================================================
Write-Host ""
Write-Host "== Zusammenfuehren =="
$all = New-Object System.Collections.Generic.List[object]
foreach ($x in $fachinfoItems) { $all.Add($x) }
foreach ($x in $githubItems) { $all.Add($x) }
foreach ($x in $actuviewItems) { $all.Add($x) }
$all = $all | Sort-Object dateIso -Descending

$allTypeTokens = New-Object System.Collections.Generic.HashSet[string]
foreach ($it in $all) { foreach ($t in ($it.type -split " / ")) { [void]$allTypeTokens.Add($t) } }
$byType = @{}
foreach ($t in $allTypeTokens) { $byType[$t] = ($all | Where-Object { ($_.type -split " / ") -contains $t }).Count }

$output = [PSCustomObject]@{
    meta = [PSCustomObject]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source      = "https://aktuar.de/de/wissen/fachinformationen/, https://github.com/DeutscheAktuarvereinigung, https://actuview.com/"
        totalItems  = $all.Count
        byType      = $byType
    }
    items = $all
}

$outPath = Join-Path $root "data\data.json"
$output | ConvertTo-Json -Depth 8 | Out-File -FilePath $outPath -Encoding utf8

Write-Host ""
Write-Host "Fertig: $($all.Count) Eintraege gespeichert in $outPath"
$byType.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }
