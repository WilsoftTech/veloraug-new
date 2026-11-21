# Step 11G: makes production's Android release signing key, once. Run by
# the owner, in PowerShell:
#
#   cd C:\Users\Wilsoft\veloraug\apps\client\android
#   powershell -ExecutionPolicy Bypass -File .\make-release-key.ps1
#
# It asks for a password, hidden, and writes:
#   - the keystore, outside the repository, in $HOME\veloraug-keys\;
#   - android\key.properties, Git-ignored, which tells Gradle where it is.
# It prints only the certificate's SHA-256 fingerprint, which is public and
# goes in apps/auth_pages/assetlinks.prod.json.
#
# Back up the keystore and its password together, somewhere off this PC (a
# password manager takes both). Every update of the app must be signed with
# this same key: if it is lost, people must uninstall and reinstall.

$ErrorActionPreference = 'Stop'

$keytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
if (-not (Test-Path $keytool)) { throw "keytool isn't at $keytool" }

$folder = Join-Path $HOME 'veloraug-keys'
$store = Join-Path $folder 'veloraug-release.jks'
$properties = Join-Path $PSScriptRoot 'key.properties'
$alias = 'veloraug'

if (Test-Path $store) { throw "$store already exists. Keep it: never make a second key." }

$first = Read-Host 'New password for the release key (at least 12 characters)' -AsSecureString
$again = Read-Host 'The same password again' -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($first))
$check = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($again))
if ($plain -ne $check) { throw 'The two passwords differ. Nothing was made.' }
if ($plain.Length -lt 12) { throw 'Use at least 12 characters. Nothing was made.' }
if ($plain -match '[\\=:#!]') { throw 'Avoid \ = : # ! in the password. Nothing was made.' }

New-Item -ItemType Directory -Force $folder | Out-Null
# keytool reads the password from the environment, never the command line.
$env:VELORAUG_KEY_PASSWORD = $plain
try {
  & $keytool -genkeypair -keystore $store -storetype PKCS12 -alias $alias `
    -keyalg RSA -keysize 4096 -validity 10000 `
    -dname 'CN=VeloraUG, O=VeloraUG, C=UG' `
    -storepass:env VELORAUG_KEY_PASSWORD -keypass:env VELORAUG_KEY_PASSWORD
  if ($LASTEXITCODE -ne 0) { throw 'keytool failed. See above.' }

  $storePath = $store -replace '\\', '/'
  @(
    '# Git-ignored. Made by make-release-key.ps1. Never commit or share it.'
    "storeFile=$storePath"
    "storePassword=$plain"
    "keyAlias=$alias"
    "keyPassword=$plain"
  ) | Set-Content -Encoding ascii $properties

  $listing = & $keytool -list -v -keystore $store -alias $alias `
    -storepass:env VELORAUG_KEY_PASSWORD
  if (($listing -join "`n") -notmatch 'SHA256:\s*([0-9A-F:]{95})') {
    throw "Couldn't read the fingerprint. The key is made: run keytool -list -v on it."
  }
  $fingerprint = $Matches[1]
} finally {
  Remove-Item Env:VELORAUG_KEY_PASSWORD -ErrorAction SilentlyContinue
  $plain = $null; $check = $null
}

Write-Host ''
Write-Host "Keystore:       $store"
Write-Host "key.properties: $properties"
Write-Host "SHA-256 fingerprint (public): $fingerprint"
Write-Host ''
Write-Host 'Now back up the keystore file and its password, off this PC.'
