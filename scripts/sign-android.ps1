param(
  [Parameter(Mandatory=$true)][string]$PackageDirectory,
  [Parameter(Mandatory=$true)][string]$Java,
  [Parameter(Mandatory=$true)][string]$ApkSignerJar,
  [Parameter(Mandatory=$true)][string]$KeyStore,
  [Parameter(Mandatory=$true)][string]$PasswordFile
)
$ErrorActionPreference='Stop'
$folder=(Resolve-Path -LiteralPath $PackageDirectory).Path
$javaPath=(Resolve-Path -LiteralPath $Java).Path
$jar=(Resolve-Path -LiteralPath $ApkSignerJar).Path
$ks=(Resolve-Path -LiteralPath $KeyStore).Path
$pass=(Resolve-Path -LiteralPath $PasswordFile).Path
$packages=@(Get-ChildItem -LiteralPath $folder -File -Filter '*.apk')
if($packages.Count -eq 0){throw 'No APKs found in the selected package directory.'}
foreach($apk in $packages){
  $signed=Join-Path $folder ($apk.BaseName+'.signed.tmp')
  if([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($signed)) -ne $folder){throw 'Output escaped package directory.'}
  & $javaPath -jar $jar sign --ks $ks --ks-key-alias onestep --ks-pass ('file:'+$pass) --v4-signing-enabled false --out $signed $apk.FullName
  if($LASTEXITCODE -ne 0){throw ('Signing failed: '+$apk.Name)}
  & $javaPath -jar $jar verify --verbose --print-certs $signed
  if($LASTEXITCODE -ne 0){throw ('Signature verification failed: '+$apk.Name)}
  Move-Item -LiteralPath $signed -Destination $apk.FullName -Force
  Write-Output ('Signed and verified '+$apk.Name)
}
