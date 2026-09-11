<#
.SYNOPSIS
  airgap-bundle icindeki 100MB ustu dosyalar GitHub'in dosya boyutu sinirini asmamak
  icin parcalara bolunmus halde tutulur (*.partNNNN). Bu script parcalari orijinal
  dosyada birlestirir ve SHA256SUMS.txt'e karsi dogrular.

.PARAMETER DeleteParts
  Basariyla dogrulanan dosyalarin .partNNNN parcalarini siler (disk yeri acar).
  Varsayilan: parcalar silinmez.

.EXAMPLE
  cd D:\airgap-bundle
  .\scripts\Reassemble-Bundle.ps1
  .\scripts\Reassemble-Bundle.ps1 -DeleteParts
#>
[CmdletBinding()]
param(
  [switch]$DeleteParts
)

$ErrorActionPreference = "Stop"
$bundleRoot = Split-Path -Parent $PSScriptRoot
$sumsFile = Join-Path $bundleRoot "SHA256SUMS.txt"

if (-not (Test-Path $sumsFile)) {
  throw "SHA256SUMS.txt bulunamadi: $sumsFile"
}

# SHA256SUMS.txt satirlari: "<hash> *./relative/path"
$expected = @{}
Get-Content $sumsFile | ForEach-Object {
  if ($_ -match '^([0-9a-fA-F]{64})\s+\*?\.?[/\\](.+)$') {
    $rel = $Matches[2] -replace '/', '\'
    $expected[$rel] = $Matches[1].ToLower()
  }
}

# Parcalari grupla: <ad>.part0000, .part0001, ... -> <ad>
# NOT: Get-ChildItem -Filter Windows'un native wildcard eslestirmesini kullanir ve
# [0-9] gibi karakter siniflarini desteklemez; bu yuzden once tum dosyalari alip
# .NET regex ile (-match) filtreliyoruz.
$partFiles = Get-ChildItem -Path $bundleRoot -Recurse -File |
  Where-Object { $_.Name -match '\.part\d{4}$' }
$groups = $partFiles | Group-Object { $_.FullName -replace '\.part\d{4}$', '' }

if ($groups.Count -eq 0) {
  Write-Host "Bolunmus parca bulunamadi (zaten birlestirilmis olabilir)." -ForegroundColor Yellow
  exit 0
}

$failed = @()

foreach ($g in $groups) {
  $targetPath = $g.Name
  $relPath = $targetPath.Substring($bundleRoot.Length + 1)
  Write-Host "Birlestiriliyor: $relPath ($($g.Group.Count) parca)"

  $parts = $g.Group | Sort-Object Name
  $outStream = [System.IO.File]::Create($targetPath)
  try {
    foreach ($p in $parts) {
      $inStream = [System.IO.File]::OpenRead($p.FullName)
      try { $inStream.CopyTo($outStream) } finally { $inStream.Close() }
    }
  } finally {
    $outStream.Close()
  }

  $actualHash = (Get-FileHash -Path $targetPath -Algorithm SHA256).Hash.ToLower()
  $expectedHash = $expected[$relPath]

  if (-not $expectedHash) {
    Write-Host "  UYARI: SHA256SUMS.txt icinde $relPath icin kayit yok, atlaniyor (dogrulanamadi)." -ForegroundColor Yellow
    continue
  }

  if ($actualHash -eq $expectedHash) {
    Write-Host "  OK  sha256=$actualHash" -ForegroundColor Green
    if ($DeleteParts) {
      $parts | Remove-Item -Force
      Write-Host "  parcalar silindi."
    }
  } else {
    Write-Host "  HATA: hash uyusmuyor!" -ForegroundColor Red
    Write-Host "    beklenen: $expectedHash"
    Write-Host "    bulunan : $actualHash"
    $failed += $relPath
  }
}

if ($failed.Count -gt 0) {
  Write-Host ""
  Write-Host "Dogrulama basarisiz olan dosyalar:" -ForegroundColor Red
  $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  exit 1
}

Write-Host ""
Write-Host "Tum dosyalar basariyla birlestirildi ve dogrulandi." -ForegroundColor Green
