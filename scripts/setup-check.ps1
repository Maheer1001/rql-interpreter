# Setup check for the RQL interpreter (Windows PowerShell 5.1 or PowerShell 7+).
#
# Verifies that your toolchain can build the project and that the built
# plc-exe binary produces the expected output for every bundled example
# program, then runs the cabal test suite.
#
# Usage (from anywhere):   powershell -ExecutionPolicy Bypass -File scripts\setup-check.ps1 [-NoTestSuite]
#                     or:  pwsh scripts/setup-check.ps1 [-NoTestSuite]
# Exit status: 0 if every check passed, 1 otherwise.

param([switch]$NoTestSuite)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Plc = Join-Path $Root 'plc'

$script:Passes = 0
$script:Fails = @()

function Write-Pass([string]$Name) {
    $script:Passes++
    Write-Host "  PASS $Name" -ForegroundColor Green
}
function Write-Fail([string]$Name, [string]$Detail = '') {
    $script:Fails += $Name
    Write-Host "  FAIL $Name" -ForegroundColor Red
    if ($Detail) { $Detail -split "`n" | ForEach-Object { Write-Host "       $_" } }
}
function Complete-Check {
    Write-Host ''
    $total = $script:Passes + $script:Fails.Count
    if ($script:Fails.Count -eq 0) {
        Write-Host "SETUP CHECK PASSED ($total checks)" -ForegroundColor Green
        exit 0
    }
    Write-Host "SETUP CHECK FAILED ($($script:Fails.Count) of $total checks failed):" -ForegroundColor Red
    $script:Fails | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

# Strip ANSI colour codes, CRs and blank lines so output compares cleanly.
function ConvertTo-CleanLines([string]$Text) {
    if ($null -eq $Text) { return @() }
    $esc = [char]27
    @(($Text -replace "$esc\[[0-9;]*m", '' -replace "`r", '') -split "`n" | Where-Object { $_.Trim() -ne '' })
}

# Run a native program with a working directory, capturing stdout and stderr.
function Invoke-Native([string]$File, [string[]]$Arguments, [string]$WorkDir) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $psi.WorkingDirectory = $WorkDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ Out = $out; Err = $errTask.Result; Code = $p.ExitCode }
}

Write-Host '== Toolchain'
$ghc = Get-Command ghc -ErrorAction SilentlyContinue
if ($ghc) {
    $ghcVer = (& ghc --numeric-version).Trim()
    if ($ghcVer -like '9.6.*') { Write-Pass "ghc $ghcVer (9.6.x required)" }
    else { Write-Fail "ghc $ghcVer found, 9.6.x required (tested with 9.6.7; ghcup install ghc 9.6.7)" }
} else {
    Write-Fail 'ghc not found on PATH (install GHC 9.6.7, e.g. with GHCup)'
}
$cabal = Get-Command cabal -ErrorAction SilentlyContinue
if ($cabal) {
    $cabalVer = (& cabal --numeric-version).Trim()
    if ($cabalVer -like '3.*') { Write-Pass "cabal $cabalVer (3.x required)" }
    else { Write-Fail "cabal $cabalVer found, 3.x required (tested with 3.12.1.0)" }
} else {
    Write-Fail 'cabal not found on PATH (install cabal-install 3.x, e.g. with GHCup)'
    Complete-Check
}

Write-Host ''
Write-Host '== Build'
$build = Invoke-Native $cabal.Source @('build', '-v1', 'exe:plc-exe') $Plc
if ($build.Code -eq 0) {
    Write-Pass 'cabal build exe:plc-exe'
} else {
    $tail = (($build.Out + $build.Err) -split "`n" | Select-Object -Last 25) -join "`n"
    Write-Fail "cabal build exe:plc-exe (if it mentions a missing package index, run 'cabal update' first)" $tail
    Complete-Check
}
$exe = (Invoke-Native $cabal.Source @('list-bin', '-v0', 'exe:plc-exe') $Plc).Out.Trim()
if ($exe -and (Test-Path -LiteralPath $exe)) { Write-Pass "plc-exe built at $exe" }
else { Write-Fail "plc-exe binary not found (cabal list-bin gave '$exe')"; Complete-Check }

Write-Host ''
Write-Host '== Example programs (plc/test/golden.txt)'
foreach ($line in Get-Content -LiteralPath (Join-Path $Plc 'test\golden.txt')) {
    $fields = @($line.Trim() -split '\s+' | Where-Object { $_ -ne '' })
    if ($fields.Count -eq 0 -or $fields[0].StartsWith('#')) { continue }
    $dir, $rql, $expected = $fields[0], $fields[1], $fields[2]
    $name = "$rql (from data/$dir)"
    $runDir = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $Plc 'data') $dir))
    $r = Invoke-Native $exe @($rql) $runDir
    $want = ConvertTo-CleanLines ([System.IO.File]::ReadAllText((Join-Path $Plc "test\expected\$expected")))
    $got = ConvertTo-CleanLines $r.Out
    if ((ConvertTo-CleanLines $r.Err).Count -gt 0) {
        Write-Fail $name ("unexpected stderr: " + ((ConvertTo-CleanLines $r.Err) -join "`n"))
    } elseif (($want -join "`n") -ceq ($got -join "`n")) {
        Write-Pass $name
    } else {
        Write-Fail $name ("--- expected ---`n" + ($want -join "`n") + "`n--- actual ---`n" + ($got -join "`n"))
    }
}

Write-Host ''
Write-Host '== Error reporting'
# plc-exe reports errors on stderr (its exit status is 0 either way), so the
# check is: nothing on stdout, and the expected error heading on stderr.
function Test-ErrorCase([string]$Rql, [string]$Heading) {
    $r = Invoke-Native $exe @($Rql) (Join-Path $Plc 'data')
    $err = (ConvertTo-CleanLines $r.Err) -join "`n"
    if ((ConvertTo-CleanLines $r.Out).Count -eq 0 -and $err.Contains($Heading)) {
        Write-Pass "$Rql -> $Heading"
    } else {
        Write-Fail "$Rql -> $Heading" ("stdout: " + $r.Out + "`nstderr: " + $err)
    }
}
Test-ErrorCase 'test/parseError.rql' '[Syntax Error]'
Test-ErrorCase 'test/type-checker/typeError.rql' '[Type Error]'
Test-ErrorCase 'test/evalError.rql' '[Evaluation Error]'

if (-not $NoTestSuite) {
    Write-Host ''
    Write-Host '== Test suite'
    $t = Invoke-Native $cabal.Source @('test') $Plc
    $log = $t.Out + $t.Err
    if ($t.Code -eq 0) {
        $summary = [regex]::Match($log, 'All tests passed \(\d+\)').Value
        Write-Pass "cabal test ($summary)"
    } else {
        $detail = ($log -split "`n" | Where-Object { $_ -match 'FAIL|rror' } | Select-Object -First 30) -join "`n"
        Write-Fail 'cabal test' $detail
    }
}

Complete-Check
