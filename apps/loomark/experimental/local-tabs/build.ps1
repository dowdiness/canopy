$ErrorActionPreference='Stop'
$trialToolchain=Join-Path $PSScriptRoot '../../../../../toolchain'
if(Test-Path -LiteralPath (Join-Path $trialToolchain 'bin/moon.exe')) {
  $env:MOON_HOME=(Resolve-Path -LiteralPath $trialToolchain).Path
  $env:PATH=$env:MOON_HOME+'\bin;'+$env:PATH
}
$env:RUST_LOG='error'
Push-Location $PSScriptRoot
try {
  moon check ../../internal/local_tabs --target js --deny-warn
  if($LASTEXITCODE){throw 'Binding check failed'}
  moon build ../../main --target js --release
  if($LASTEXITCODE){throw 'Loomark build failed'}
  moon build engine/main --target js --release
  if($LASTEXITCODE){throw 'EGW Worker build failed'}
  moon build fixture --target js --release
  if($LASTEXITCODE){throw 'Lifecycle fixture build failed'}
  Copy-Item -LiteralPath '_build/js/release/build/dowdiness/loomark/main/main.js' -Destination 'loomark.js'
  Copy-Item -LiteralPath '_build/js/release/build/trial/local_tabs/main/main.js' -Destination 'egw.js'
  Copy-Item -LiteralPath '_build/js/release/build/dowdiness/loomark/experimental/local-tabs/fixture/fixture.js' -Destination 'fixture.js'
} finally {Pop-Location}
