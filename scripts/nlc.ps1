# Driver for the self-hosted compiler on Windows: compile to LLVM IR with nlc-selfhost.exe, then link with clang.
#   nlc.ps1 build <package> [-o out.exe]    compile and link a program
#   nlc.ps1 run   <package> [args...]       build into a temporary directory and run
#   nlc.ps1 link  <file.ll> -o out.exe      link IR the compiler already wrote
# NLC_SELFHOST names the compiler (default: nlc-selfhost.exe next to this script or in the parent directory);
# NLC_RUNTIME_DIR names the directory holding nl_runtime.c (default: ..\runtime or .\runtime);
# NLC_OPT_LEVEL is 1 (default) or 3. `test` is not available on Windows yet.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-Compiler {
    if ($env:NLC_SELFHOST) { return $env:NLC_SELFHOST }
    foreach ($candidate in @("$here\nlc-selfhost.exe", "$here\..\nlc-selfhost.exe")) {
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    throw "nlc: cannot find nlc-selfhost.exe; set NLC_SELFHOST"
}

function Find-Runtime {
    if ($env:NLC_RUNTIME_DIR) { return $env:NLC_RUNTIME_DIR }
    foreach ($candidate in @("$here\..\runtime", "$here\runtime")) {
        if (Test-Path "$candidate\nl_runtime.c") { return (Resolve-Path $candidate).Path }
    }
    throw "nlc: cannot find runtime\nl_runtime.c; set NLC_RUNTIME_DIR"
}

function Link-Ir([string]$Ir, [string]$Output) {
    $runtime = ''; $build = ''; $stack = ''
    foreach ($line in Get-Content $Ir -TotalCount 12) {
        if ($line -like '; nlc.runtime *') { $runtime = $line.Substring(14) }
        elseif ($line -like '; nlc.build *') { $build = $line.Substring(12) }
        elseif ($line -like '; nlc.stack *') { $stack = $line.Substring(12) }
    }
    if ($runtime -ne 'c') { throw "nlc: only the C runtime is supported on Windows (found '$runtime')" }
    $level = if ($env:NLC_OPT_LEVEL) { $env:NLC_OPT_LEVEL } else { '1' }
    $flags = @("-O$level", '-D_CRT_SECURE_NO_WARNINGS', '-fuse-ld=lld')
    if ($build -eq 'test') { $flags += '-DNLC_TEST_BUILD=1' }
    if ($stack -eq 'offset') { $flags += '-DNLC_STACK_MODE_OFFSET=1' }
    & clang @flags $Ir "$(Find-Runtime)\nl_runtime.c" -o $Output
    if ($LASTEXITCODE -ne 0) { throw "nlc: clang failed" }
}

function Compile-Package([string]$Package, [string]$Ir) {
    & (Find-Compiler) build $Package -o $Ir --runtime=c
    if ($LASTEXITCODE -ne 0) { throw "nlc: the compiler rejected $Package" }
}

$command = $args[0]
$rest = @($args | Select-Object -Skip 1)
switch ($command) {
    'build' {
        $package = ''; $output = ''
        for ($i = 0; $i -lt $rest.Count; $i++) {
            if ($rest[$i] -eq '-o') { $output = $rest[++$i] } else { $package = $rest[$i] }
        }
        if (-not $package) { throw 'usage: nlc.ps1 build <package> [-o out.exe]' }
        if (-not $output) { $output = (Split-Path -Leaf $package) + '.exe' }
        $ir = "$output.ll"
        Compile-Package $package $ir
        Link-Ir $ir $output
        Remove-Item $ir
    }
    'run' {
        if ($rest.Count -lt 1) { throw 'usage: nlc.ps1 run <package> [args...]' }
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory $work | Out-Null
        try {
            Compile-Package $rest[0] "$work\program.ll"
            Link-Ir "$work\program.ll" "$work\program.exe"
            & "$work\program.exe" @($rest | Select-Object -Skip 1)
            exit $LASTEXITCODE
        } finally { Remove-Item -Recurse -Force $work }
    }
    'link' {
        if ($rest.Count -ne 3 -or $rest[1] -ne '-o') { throw 'usage: nlc.ps1 link <file.ll> -o out.exe' }
        Link-Ir $rest[0] $rest[2]
    }
    default { throw 'usage: nlc.ps1 build|run|link ... (see the header of this script)' }
}
