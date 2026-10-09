$ErrorActionPreference='Stop'
$trialToolchain=Join-Path $PSScriptRoot '../../../../../toolchain'
if(Test-Path -LiteralPath (Join-Path $trialToolchain 'bin/moon.exe')) {
  $env:MOON_HOME=(Resolve-Path -LiteralPath $trialToolchain).Path
  $env:PATH=$env:MOON_HOME+'\bin;'+$env:PATH
}
$env:RUST_LOG='error'
Push-Location $PSScriptRoot
try {
  node build.mjs
  if($LASTEXITCODE){throw 'Experiment build failed'}
} finally {Pop-Location}
