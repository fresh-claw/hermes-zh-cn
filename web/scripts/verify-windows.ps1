param(
  [string]$Version = "2026.06.12.1"
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) {
    throw $Message
  }
}

function Wait-Http([string]$Url) {
  for ($i = 0; $i -lt 30; $i++) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2 | Out-Null
      return
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  throw "local HTTP server did not become ready"
}

function New-FakeNodeExe([string]$Path, [string]$Version) {
  $className = "NodeStub" + ([guid]::NewGuid().ToString("N"))
  $source = @"
using System;
public static class $className {
  public static int Main(string[] args) {
    Console.WriteLine("$Version");
    return 0;
  }
}
"@
  Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $Path -OutputType ConsoleApplication
}

function New-FakeBashExe([string]$Path, [string]$Version) {
  $className = "BashStub" + ([guid]::NewGuid().ToString("N"))
  $source = @"
using System;
using System.IO;
using System.Text;
public static class $className {
  public static int Main(string[] args) {
    if (args.Length > 0 && args[0] == "-lc") {
      Console.WriteLine(Environment.GetEnvironmentVariable("HERMES_HOME") ?? "");
      return 0;
    }

    string installHome = Environment.GetEnvironmentVariable("XIAOMA_HERMES_HOME") ?? Path.Combine(Path.GetTempPath(), "xiaoma-hermes");
    string hermesHome = Environment.GetEnvironmentVariable("HERMES_HOME") ?? Path.Combine(Path.GetTempPath(), ".hermes");
    string sourceRoot = Environment.GetEnvironmentVariable("XIAOMA_HERMES_SOURCE_ROOT") ?? "";
    string releaseDir = Path.Combine(installHome, "releases", "$Version");
    Directory.CreateDirectory(releaseDir);
    File.WriteAllText(Path.Combine(releaseDir, "PATCH_STATUS"), "{\"state\":\"applied\",\"patched\":[\"hermes_cli/banner.py\"]}", Encoding.UTF8);

    if (!String.IsNullOrWhiteSpace(sourceRoot)) {
      string banner = Path.Combine(sourceRoot, "hermes_cli", "banner.py");
      Directory.CreateDirectory(Path.GetDirectoryName(banner));
      File.AppendAllText(banner, "\n# 爱马仕机器人\n", Encoding.UTF8);
    }

    Directory.CreateDirectory(hermesHome);
    File.WriteAllText(Path.Combine(hermesHome, "config.yaml"), "display:\n  language: zh\n", Encoding.UTF8);
    return 0;
  }
}
"@
  Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $Path -OutputType ConsoleApplication
}

function Invoke-NodeBootstrapVerification {
  if (-not $IsWindows) {
    Write-Host "node bootstrap verification skipped outside Windows"
    return
  }

  $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("xiaoma-hermes-node-verify-" + [guid]::NewGuid().ToString("N"))
  $serverRoot = Join-Path $temp "server"
  $oldNodeBin = Join-Path $temp "old-node"
  $fakeNodeRoot = Join-Path $temp "fake-node"
  $fakeNodeDir = Join-Path $fakeNodeRoot "node-v22.22.3-win-x64"
  $home = Join-Path $temp "home"
  $hermesHome = Join-Path $home ".hermes"
  $sourceRoot = Join-Path $temp "source"
  $installHome = Join-Path $temp "xiaoma"
  $bin = Join-Path $temp "bin"
  $fakeBashDir = Join-Path $hermesHome "git\usr\bin"
  New-Item -ItemType Directory -Force -Path $serverRoot, $oldNodeBin, $fakeNodeDir, $home, $hermesHome, $sourceRoot, (Join-Path $sourceRoot "hermes_cli"), $bin, $fakeBashDir | Out-Null

  New-FakeNodeExe -Path (Join-Path $oldNodeBin "node.exe") -Version "v18.20.0"
  New-FakeNodeExe -Path (Join-Path $fakeNodeDir "node.exe") -Version "v22.22.3"
  New-FakeBashExe -Path (Join-Path $fakeBashDir "bash.exe") -Version $Version

  $zipDir = Join-Path $serverRoot "node/v22.22.3"
  New-Item -ItemType Directory -Force -Path $zipDir | Out-Null
  Compress-Archive -Path $fakeNodeDir -DestinationPath (Join-Path $zipDir "node-v22.22.3-win-x64.zip") -Force
  Set-Content -Path (Join-Path $serverRoot "node/index.json") -Encoding UTF8 -Value '[{"version":"v22.22.3","files":["win-x64-zip"]}]'
  Copy-Item -Force (Join-Path $Root "install.sh") (Join-Path $serverRoot "install.sh")

  $officialStub = @'
param(
  [switch]$IncludeDesktop,
  [switch]$NonInteractive
)
# hermes-agent official install stub for Windows verification.
$ErrorActionPreference = "Stop"
$nodeVersion = (& node --version).Trim()
if ($nodeVersion -ne "v22.22.3") {
  throw "expected managed Node.js v22.22.3, got $nodeVersion"
}
$hermesHome = $env:HERMES_HOME
if ([string]::IsNullOrWhiteSpace($hermesHome)) {
  throw "HERMES_HOME missing"
}
$cmdDir = Join-Path $hermesHome "hermes-agent\venv\Scripts"
$desktopDir = Join-Path $hermesHome "hermes-agent\apps\desktop\release\win-unpacked"
New-Item -ItemType Directory -Force -Path $cmdDir, $desktopDir | Out-Null
Set-Content -Path (Join-Path $cmdDir "hermes.cmd") -Encoding ASCII -Value "@echo Hermes Agent v0.16.0"
Set-Content -Path (Join-Path $desktopDir "Hermes.exe") -Encoding ASCII -Value "fake desktop"
'@
  Set-Content -Path (Join-Path $serverRoot "official-hermes-install.ps1") -Encoding UTF8 -Value $officialStub

  $fakeHermes = Join-Path $bin "hermes"
  Set-Content -Path $fakeHermes -Encoding UTF8 -Value @'
#!/usr/bin/env bash
printf 'Hermes Agent v0.16.0\n'
'@
  $fakePython3 = Join-Path $bin "python3"
  Set-Content -Path $fakePython3 -Encoding UTF8 -Value @'
#!/usr/bin/env bash
python "$@"
'@
  Set-Content -Path (Join-Path $sourceRoot "hermes_cli/banner.py") -Encoding UTF8 -Value @'
VERSION="0.16.0"
RELEASE_DATE="2026-06-05"
base = f"Hermes Agent v{VERSION} ({RELEASE_DATE})"
'@

  $oldPath = $env:Path
  $oldHome = $env:HOME
  $oldHermesHome = $env:HERMES_HOME
  $oldNodeIndexes = $env:XIAOMA_HERMES_NODE_INDEX_URLS
  $oldOfficialUrls = $env:XIAOMA_HERMES_OFFICIAL_INSTALL_URLS
  $oldSourceRoot = $env:XIAOMA_HERMES_SOURCE_ROOT
  $oldInstallHome = $env:XIAOMA_HERMES_HOME
  $oldRealHermes = $env:XIAOMA_HERMES_REAL_HERMES
  $oldSkipWrapper = $env:XIAOMA_HERMES_SKIP_WRAPPER
  $oldQuiet = $env:XIAOMA_HERMES_QUIET

  $port = 18766
  $server = $null
  try {
    $env:Path = "$oldNodeBin;$bin;$env:Path"
    $env:HOME = $home
    $env:HERMES_HOME = $hermesHome
    $env:XIAOMA_HERMES_SOURCE_ROOT = $sourceRoot
    $env:XIAOMA_HERMES_HOME = $installHome
    $env:XIAOMA_HERMES_REAL_HERMES = $fakeHermes
    $env:XIAOMA_HERMES_SKIP_WRAPPER = "1"
    $env:XIAOMA_HERMES_QUIET = "1"
    $env:XIAOMA_HERMES_NODE_INDEX_URLS = "http://127.0.0.1:$port/node/index.json"
    $env:XIAOMA_HERMES_OFFICIAL_INSTALL_URLS = "http://127.0.0.1:$port/official-hermes-install.ps1"

    $server = Start-Process -FilePath python -ArgumentList @("-m", "http.server", "$port", "--bind", "127.0.0.1") -WorkingDirectory $serverRoot -PassThru -WindowStyle Hidden
    Wait-Http "http://127.0.0.1:$port/install.sh"

    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "install.ps1") -BaseUrl "http://127.0.0.1:$port"
    if ($LASTEXITCODE -ne 0) {
      throw "install.ps1 node bootstrap exited with $LASTEXITCODE"
    }

    $managedNode = Join-Path $hermesHome "node\node.exe"
    Assert-True (Test-Path $managedNode) "managed node.exe was not installed"
    Assert-True (((& $managedNode --version).Trim()) -eq "v22.22.3") "managed node.exe version mismatch"
    Assert-True (Test-Path (Join-Path $hermesHome "hermes-agent\apps\desktop\release\win-unpacked\Hermes.exe")) "desktop stub was not created"

    $updatedBanner = Get-Content -Raw -Path (Join-Path $sourceRoot "hermes_cli/banner.py")
    Assert-True ($updatedBanner.Contains("爱马仕机器人")) "banner text was not localized after node bootstrap"

    Write-Host "windows node bootstrap verification passed: $Version"
  } finally {
    if ($server -and -not $server.HasExited) {
      Stop-Process -Id $server.Id -Force
    }
    $env:Path = $oldPath
    $env:HOME = $oldHome
    $env:HERMES_HOME = $oldHermesHome
    $env:XIAOMA_HERMES_NODE_INDEX_URLS = $oldNodeIndexes
    $env:XIAOMA_HERMES_OFFICIAL_INSTALL_URLS = $oldOfficialUrls
    $env:XIAOMA_HERMES_SOURCE_ROOT = $oldSourceRoot
    $env:XIAOMA_HERMES_HOME = $oldInstallHome
    $env:XIAOMA_HERMES_REAL_HERMES = $oldRealHermes
    $env:XIAOMA_HERMES_SKIP_WRAPPER = $oldSkipWrapper
    $env:XIAOMA_HERMES_QUIET = $oldQuiet
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
  }
}

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root "install.ps1"), [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-True (($parseErrors | Measure-Object).Count -eq 0) "install.ps1 parse failed"

$installPs1 = Get-Content -Raw -Path (Join-Path $Root "install.ps1")
Assert-True ($installPs1.Contains("v$Version")) "install.ps1 version marker mismatch"
Assert-True ($installPs1.Contains("Download-OfficialInstaller")) "official installer validation missing"
Assert-True ($installPs1.Contains("Move-HermesAgentSourceAside")) "official repair fallback missing"
Assert-True ($installPs1.Contains("Ensure-WindowsNode")) "Windows Node.js preparation missing"
Assert-True ($installPs1.Contains("cdn.npmmirror.com/binaries/node/index.json")) "Node.js China mirror missing"
Assert-True ($installPs1.Contains("nodejs.org/dist/index.json")) "Node.js official fallback missing"
Assert-True ($installPs1.Contains("HERMES_GIT_BASH_PATH")) "Git Bash environment override missing"
Assert-True ($installPs1.Contains("git\usr\bin\bash.exe")) "PortableGit usr bash fallback missing"
Assert-True ($installPs1.Contains("Programs\Git\bin\bash.exe")) "Git for Windows user install fallback missing"

$exeBytes = [System.IO.File]::ReadAllBytes((Join-Path $Root "Hermes-zh-CN-Setup.exe"))
$exeText = [System.Text.Encoding]::UTF8.GetString($exeBytes)
Assert-True ($exeText.Contains("v$Version")) "windows exe embedded version marker mismatch"

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("xiaoma-hermes-win-verify-" + [guid]::NewGuid().ToString("N"))
$home = Join-Path $temp "home"
$bin = Join-Path $temp "bin"
$hermesHome = Join-Path $home ".hermes"
$sourceRoot = Join-Path $temp "source"
$installHome = Join-Path $temp "xiaoma"
$fakeBashDir = Join-Path $hermesHome "git\usr\bin"
New-Item -ItemType Directory -Force -Path $bin, $hermesHome, $sourceRoot, (Join-Path $sourceRoot "hermes_cli"), $fakeBashDir | Out-Null
New-FakeBashExe -Path (Join-Path $fakeBashDir "bash.exe") -Version $Version

$fakeHermes = Join-Path $bin "hermes"
Set-Content -Path $fakeHermes -Encoding UTF8 -Value @'
#!/usr/bin/env bash
printf 'Hermes Agent v0.16.0\n'
'@
$fakeHermesCmd = Join-Path $bin "hermes.cmd"
Set-Content -Path $fakeHermesCmd -Encoding ASCII -Value "@echo Hermes Agent v0.16.0"

$fakePython3 = Join-Path $bin "python3"
Set-Content -Path $fakePython3 -Encoding UTF8 -Value @'
#!/usr/bin/env bash
python "$@"
'@

$bannerPath = Join-Path $sourceRoot "hermes_cli/banner.py"
Set-Content -Path $bannerPath -Encoding UTF8 -Value @'
VERSION="0.16.0"
RELEASE_DATE="2026-06-05"
base = f"Hermes Agent v{VERSION} ({RELEASE_DATE})"
'@

$desktopDir = Join-Path $hermesHome "hermes-agent/apps/desktop/release/win-unpacked"
New-Item -ItemType Directory -Force -Path $desktopDir | Out-Null
Set-Content -Path (Join-Path $desktopDir "Hermes.exe") -Encoding ASCII -Value "fake"

if ($IsWindows) {
  $env:PATH = "$bin;$env:PATH"
} else {
  $env:PATH = "$bin`:$env:PATH"
}
$env:HOME = $home
$env:HERMES_HOME = $hermesHome
$env:XIAOMA_HERMES_HOME = $installHome
$env:XIAOMA_HERMES_SOURCE_ROOT = $sourceRoot
$env:XIAOMA_HERMES_REAL_HERMES = $fakeHermes
$env:XIAOMA_HERMES_SKIP_OFFICIAL_INSTALL = "1"
$env:XIAOMA_HERMES_SKIP_WRAPPER = "1"
$env:XIAOMA_HERMES_QUIET = "1"

$port = 18765
$server = Start-Process -FilePath python -ArgumentList @("-m", "http.server", "$port", "--bind", "127.0.0.1") -WorkingDirectory $Root -PassThru -WindowStyle Hidden
try {
  Wait-Http "http://127.0.0.1:$port/install.sh"
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "install.ps1") -BaseUrl "http://127.0.0.1:$port" -SkipOfficial
  if ($LASTEXITCODE -ne 0) {
    throw "install.ps1 exited with $LASTEXITCODE"
  }

  $statusPath = Join-Path $installHome "releases/$Version/PATCH_STATUS"
  Assert-True (Test-Path $statusPath) "PATCH_STATUS was not created"
  $status = Get-Content -Raw -Path $statusPath | ConvertFrom-Json
  Assert-True (($status.patched -contains "hermes_cli/banner.py") -or ($status.state -eq "partial")) "banner patch did not run"

  $updatedBanner = Get-Content -Raw -Path $bannerPath
  Assert-True ($updatedBanner.Contains("爱马仕机器人")) "banner text was not localized"

  $configPath = Join-Path $hermesHome "config.yaml"
  Assert-True (Test-Path $configPath) "config.yaml was not created"
  Assert-True ((Get-Content -Raw -Path $configPath).Contains("language: zh")) "config language was not set"

  Write-Host "windows verification passed: $Version"
} finally {
  if ($server -and -not $server.HasExited) {
    Stop-Process -Id $server.Id -Force
  }
  Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}

Invoke-NodeBootstrapVerification
