# Aktualisiert data/data.json mit allen DAV-Fachinformationen der Arten
# Ergebnisbericht, Hinweis, Richtlinie und Use Case von https://aktuar.de
#
# Quelle: die oeffentliche Solr-Suchschnittstelle, die auch die Filter auf
# https://aktuar.de/de/wissen/fachinformationen/ bedient. Kein Login noetig
# fuer Titel/Datum/Thema/Kurzbeschreibung; Mitgliederinhalte bleiben verlinkt,
# aber nicht im Volltext uebernommen.
#
# Aufruf:  pwsh scripts/update-data.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$headers = @{ "User-Agent" = "Mozilla/5.0 (compatible; DAV-Fachinfo-Uebersicht/1.0; +https://github.com/)" }
$types = @("Ergebnisbericht", "Hinweis", "Richtlinie", "Use Case")

function Parse-DavDate($s) {
    try { return [datetime]::ParseExact($s, "dd.MM.yyyy", $null) } catch { return $null }
}

function Strip-Html($s) {
    if (-not $s) { return "" }
    $s = [regex]::Replace($s, "<[^>]+>", " ")
    $s = $s -replace "&nbsp;", " " -replace "&amp;", "&" -replace "&quot;", '"' -replace "&#39;", "'"
    $s = [regex]::Replace($s, "\s+", " ")
    return $s.Trim()
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

function Get-ShortDescription($content, $teaser) {
    $text = Strip-Html $content
    if (-not $text) { $text = Strip-Html $teaser }
    if (-not $text) { return "" }
    $text = $text -replace "^Überblick\s*", ""
    $protected = Protect-Abbrev $text
    $sentences = [regex]::Matches($protected, "[^.!?]+[.!?]+") | ForEach-Object { Restore-Abbrev $_.Value.Trim() }
    if ($sentences.Count -eq 0) { $sentences = @($text) }
    $out = ""; $count = 0
    foreach ($s in $sentences) {
        if ($count -ge 3 -or ($out.Length + $s.Length) -gt 420) { break }
        $out += " " + $s; $count++
    }
    $out = $out.Trim()
    if (-not $out) { $out = $text.Substring(0, [Math]::Min(300, $text.Length)) + "…" }
    return $out
}

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

Write-Host "== Schritt 1/2: Rohdaten von aktuar.de laden =="
$raw = New-Object System.Collections.Generic.List[object]

foreach ($type in $types) {
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
            if ($r.tags -and $r.tags.tag) { $tagList = @($r.tags.tag) }
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

Write-Host "== Schritt 2/2: Aufbereiten, deduplizieren, JSON schreiben =="
foreach ($item in $raw) {
    Add-Member -InputObject $item -NotePropertyName "parsedDate" -NotePropertyValue (Parse-DavDate $item.publishedAt) -Force
}

$clean = New-Object System.Collections.Generic.List[object]
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

    $clean.Add([PSCustomObject]@{
        type             = ($allTypesForUrl -join " / ")
        title            = ($primary.title -replace "\s+", " ").Trim()
        date             = $primary.publishedAt
        dateIso          = $iso
        theme            = $primary.category
        tags             = $primary.tags
        committee        = Get-Committee $primary.content
        description      = Get-ShortDescription $primary.content $primary.teaser
        url              = $(if ($hasDirectLink) { $primary.url } else { "https://aktuar.de/de/wissen/fachinformationen/" })
        hasDirectLink    = $hasDirectLink
        locked           = ($primary.locked -eq "true")
        isPdf            = ($primary.specType -eq "download")
        previousVersions = $prevVersions
    })
}

$clean = $clean | Sort-Object dateIso -Descending

$byType = @{}
foreach ($t in $types) { $byType[$t] = ($clean | Where-Object { $_.type -like "*$t*" }).Count }

$output = [PSCustomObject]@{
    meta = [PSCustomObject]@{
        generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source      = "https://aktuar.de/de/wissen/fachinformationen/"
        totalItems  = $clean.Count
        byType      = $byType
    }
    items = $clean
}

$outPath = Join-Path $root "data\data.json"
$output | ConvertTo-Json -Depth 8 | Out-File -FilePath $outPath -Encoding utf8

Write-Host ""
Write-Host "Fertig: $($clean.Count) Eintraege gespeichert in $outPath"
