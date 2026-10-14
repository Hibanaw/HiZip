# Builds a signed MSIX for Windows. Usage: pwsh scripts/build_msix.ps1 [-Pfx path -PfxPassword pw]
# Without -Pfx a self-signed dev certificate (CN=Hibanaw) is created in build/.
param(
  [string]$Pfx,
  [string]$PfxPassword = 'hizip-dev',
  [string]$Publisher = 'CN=Hibanaw'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.*\x64\makeappx.exe" |
  Sort-Object FullName -Descending | Select-Object -First 1 | Split-Path
$release = "$root\build\windows\x64\runner\Release"
$out = "$root\build\windows\x64\runner\hizip.msix"

# Builds the app and writes AppxManifest.xml/assets; packing is redone below
# because the msix package's bundled makeappx.exe fails on some machines.
$ErrorActionPreference = 'Continue'
$createLog = dart run msix:create *>&1 | Out-String
$ErrorActionPreference = 'Stop'
$manifestPath = "$release\AppxManifest.xml"
if (-not (Test-Path $manifestPath)) {
  $tail = ($createLog -split "`n" | Select-Object -Last 40) -join '%0A'
  if ($env:GITHUB_ACTIONS) { Write-Host "::error::msix:create failed%0A$tail" }
  throw 'AppxManifest.xml was not generated'
}
$manifest = Get-Content $manifestPath -Raw
$manifest = $manifest -replace 'Publisher="[^"]*"', "Publisher=`"$Publisher`""
Set-Content $manifestPath $manifest -Encoding utf8

& "$sdk\makeappx.exe" pack /o /d $release /p $out
if ($LASTEXITCODE) { throw 'makeappx failed' }

if (-not $Pfx) {
  $Pfx = "$root\build\hizip-dev.pfx"
  if (-not (Test-Path $Pfx)) {
    $cert = New-SelfSignedCertificate -Type Custom -Subject $Publisher -KeyUsage DigitalSignature `
      -FriendlyName 'HiZip Dev' -CertStoreLocation Cert:\CurrentUser\My `
      -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
    $pw = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $Pfx -Password $pw | Out-Null
    Export-Certificate -Cert $cert -FilePath "$root\build\hizip-dev.cer" | Out-Null
  }
}
& "$sdk\signtool.exe" sign /fd SHA256 /f $Pfx /p $PfxPassword $out
if ($LASTEXITCODE) { throw 'signtool failed' }
Write-Host "MSIX: $out"
