# Builds an MSIX for Windows. Usage:
#   pwsh scripts/build_msix.ps1         # sideload build signed with a dev certificate
#   pwsh scripts/build_msix.ps1 -Store  # unsigned package for Partner Center
# -Store uses the product identity reserved in Partner Center (Product
# management > Product identity) and leaves the package unsigned: the
# Microsoft Store signs it on ingestion. Override the values with -IdentityName,
# -Publisher and -PublisherDisplayName. Raise msix_version in pubspec.yaml
# (last part stays 0) for every new submission.
# Without -Pfx a self-signed dev certificate (CN=Hibanaw) is created in build/.
param(
  [string]$Pfx,
  [string]$PfxPassword = 'hizip-dev',
  [string]$Publisher,
  [string]$IdentityName,
  [string]$PublisherDisplayName,
  [switch]$Store
)
$ErrorActionPreference = 'Stop'
# Surface the failure as a workflow annotation: CI logs are not readable without
# a token, but annotations are public.
trap {
  if ($env:GITHUB_ACTIONS) {
    $msg = "$($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)" -replace "`r?`n", '%0A'
    Write-Host "::error::$msg"
  }
  break
}
if ($Store) {
  if (-not $IdentityName) { $IdentityName = 'Hibanaw.HiZip' }
  if (-not $Publisher) { $Publisher = 'CN=0B04E7E3-18BF-4700-A7E5-F525D1698514' }
  if (-not $PublisherDisplayName) { $PublisherDisplayName = 'Hibanaw' }
} elseif (-not $Publisher) {
  $Publisher = 'CN=Hibanaw'
}
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.*\x64\makeappx.exe" |
  Sort-Object FullName -Descending | Select-Object -First 1 | Split-Path
$release = "$root\build\windows\x64\runner\Release"
$out = "$root\build\windows\x64\runner\hizip.msix"

# A failed build must stop here instead of repackaging the previous output.
flutter build windows --release
if ($LASTEXITCODE) { throw 'flutter build windows failed' }

# Writes AppxManifest.xml/assets; packing is redone below because the msix
# package's bundled makeappx.exe fails on some machines.
$ErrorActionPreference = 'Continue'
dart run msix:create *> $null
$ErrorActionPreference = 'Stop'
$manifestPath = "$release\AppxManifest.xml"
if (-not (Test-Path $manifestPath)) { throw 'AppxManifest.xml was not generated' }
if (-not (Test-Path "$release\hizip_shell.dll")) { throw 'hizip_shell.dll missing from the release build' }
# Only used by the unpackaged sparse-package registration.
Remove-Item "$release\shell_package" -Recurse -Force -ErrorAction SilentlyContinue

$manifest = Get-Content $manifestPath -Raw
$manifest = $manifest -replace 'Publisher="[^"]*"', "Publisher=`"$Publisher`""
if ($IdentityName) { $manifest = $manifest -replace '(<Identity Name=")[^"]*"', "`${1}$IdentityName`"" }
if ($PublisherDisplayName) {
  $manifest = $manifest -replace '(<PublisherDisplayName>)[^<]*', "`${1}$PublisherDisplayName"
}

# Windows 11 context menu (windows/shell_ext), declared statically: a packaged
# app cannot register it at run time. The execution alias lets the handler start
# the app; Windows 10 ignores the Explorer extension.
$clsid = '7A3C9E52-5B1D-4F6E-9A40-2C8D1E6F0B73'
$extensions = @"

          <uap3:Extension Category="windows.appExecutionAlias" Executable="hizip.exe" EntryPoint="Windows.FullTrustApplication">
            <uap3:AppExecutionAlias>
              <desktop:ExecutionAlias Alias="hizip.exe" />
            </uap3:AppExecutionAlias>
          </uap3:Extension>
          <desktop4:Extension Category="windows.fileExplorerContextMenus">
            <desktop4:FileExplorerContextMenus>
              <desktop5:ItemType Type="*"><desktop5:Verb Id="HiZip" Clsid="$clsid" /></desktop5:ItemType>
              <desktop5:ItemType Type="Directory"><desktop5:Verb Id="HiZip" Clsid="$clsid" /></desktop5:ItemType>
            </desktop4:FileExplorerContextMenus>
          </desktop4:Extension>
          <com:Extension Category="windows.comServer">
            <com:ComServer>
              <com:SurrogateServer DisplayName="HiZip context menu">
                <com:Class Id="$clsid" Path="hizip_shell.dll" ThreadingModel="STA" />
              </com:SurrogateServer>
            </com:ComServer>
          </com:Extension>
"@
if ($manifest -notmatch '</Extensions>') { throw 'Unexpected manifest: no <Extensions> to extend' }
$manifest = $manifest -replace '(?s)(</uap:Extension>\s*)(</Extensions>)', "`$1$extensions`n        `$2"
$manifest = $manifest -replace 'IgnorableNamespaces="[^"]*"', 'IgnorableNamespaces="uap3 desktop desktop4 desktop5 com"'
Set-Content $manifestPath $manifest -Encoding utf8

& "$sdk\makeappx.exe" pack /o /d $release /p $out
if ($LASTEXITCODE) { throw 'makeappx failed' }

if ($Store) {
  Write-Host "MSIX (unsigned, for Partner Center): $out"
  return
}

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
