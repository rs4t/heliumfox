# HeliumFox installer + Helium's start page (Simple-start by SpringDallies)
# Usage: irm https://raw.githubusercontent.com/rs4t/heliumfox/main/install-with-startpage.ps1 | iex
#
# 1. Installs HeliumFox (same as install.ps1).
# 2. Downloads Simple-start (https://github.com/SpringDallies/Simple-start) to
#    %APPDATA%\Mozilla\Firefox\simple-start.
# 3. Makes Firefox open it for new tabs and as the homepage, using two small
#    config files in the Firefox install folder (one Windows admin prompt).

function Install-HeliumFoxStartPage {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $utf8 = New-Object Text.UTF8Encoding $false

    # ---- 1. The theme ----------------------------------------------------------
    $themeScript = if ($env:HELIUMFOX_LOCAL) { Get-Content (Join-Path $env:HELIUMFOX_LOCAL 'install.ps1') -Raw }
                   else { Invoke-RestMethod 'https://raw.githubusercontent.com/rs4t/heliumfox/main/install.ps1' }
    Invoke-Expression $themeScript

    Write-Host '  Start page (Simple-start by SpringDallies)' -ForegroundColor Cyan
    Write-Host ''

    # ---- 2. Download Simple-start ---------------------------------------------
    $pageDir = Join-Path $env:APPDATA 'Mozilla\Firefox\simple-start'
    $tmp = Join-Path $env:TEMP ('simple-start-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'simple-start.zip'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/SpringDallies/Simple-start/archive/refs/heads/main.zip' -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $extracted = Get-ChildItem $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'index.html') } | Select-Object -First 1
    if (-not $extracted) {
        Write-Host '  Could not find Simple-start in the download, nothing else was changed.' -ForegroundColor Red
        return
    }
    New-Item -ItemType Directory -Force -Path $pageDir | Out-Null
    Copy-Item (Join-Path $extracted.FullName '*') $pageDir -Recurse -Force
    Remove-Item $tmp -Recurse -Force
    Write-Host "  Downloaded Simple-start to: $pageDir"

    $pageUrl = 'file:///' + ((Join-Path $pageDir 'index.html') -replace '\\', '/')

    # ---- 3. Firefox config: new tab + homepage --------------------------------
    $ffInstall = $env:HELIUMFOX_FIREFOX_DIR
    if (-not $ffInstall) {
        foreach ($key in 'HKLM:\SOFTWARE\Mozilla\Mozilla Firefox', 'HKLM:\SOFTWARE\WOW6432Node\Mozilla\Mozilla Firefox', 'HKCU:\SOFTWARE\Mozilla\Mozilla Firefox') {
            $ver = (Get-ItemProperty $key -ErrorAction SilentlyContinue).CurrentVersion
            if ($ver) {
                $dir = (Get-ItemProperty "$key\$ver\Main" -ErrorAction SilentlyContinue).'Install Directory'
                if ($dir -and (Test-Path (Join-Path $dir 'firefox.exe'))) { $ffInstall = $dir; break }
            }
        }
    }
    if (-not $ffInstall) { $ffInstall = Join-Path $env:ProgramFiles 'Mozilla Firefox' }
    if (-not (Test-Path (Join-Path $ffInstall 'firefox.exe'))) {
        Write-Host '  Could not find the Firefox install folder. Set up the new tab page by hand (see the README).' -ForegroundColor Red
        return
    }

    $cfgPath = Join-Path $ffInstall 'mozilla.cfg'
    if ((Test-Path $cfgPath) -and ((Get-Content $cfgPath -Raw) -notmatch 'HeliumFox')) {
        Write-Host "  $cfgPath already exists and isn't from HeliumFox, so it was left alone." -ForegroundColor Yellow
        Write-Host '  Add the new tab lines from newtab/mozilla.cfg in the repo to it by hand.' -ForegroundColor Yellow
        return
    }

    $cfg = @"
// HeliumFox: new tab page + homepage (this first line must stay a comment).
// Delete this file and defaults\pref\autoconfig.js to undo.
try {
  const { AboutNewTab } = ChromeUtils.importESModule("resource:///modules/AboutNewTab.sys.mjs");
  AboutNewTab.newTabURL = "$pageUrl";
} catch (e) {
  Components.utils.reportError(e);
}
// Default homepage (you can still change it in Settings > Home)
defaultPref("browser.startup.homepage", "$pageUrl");
"@
    $autoconfig = @"
// HeliumFox: loads mozilla.cfg from the Firefox install folder.
pref("general.config.filename", "mozilla.cfg");
pref("general.config.obscure_value", 0);
pref("general.config.sandbox_enabled", false);
"@
    $stage = Join-Path $env:TEMP ('heliumfox-cfg-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    [IO.File]::WriteAllText((Join-Path $stage 'mozilla.cfg'), $cfg, $utf8)
    [IO.File]::WriteAllText((Join-Path $stage 'autoconfig.js'), $autoconfig, $utf8)

    $copy = "Copy-Item -LiteralPath '$stage\mozilla.cfg' -Destination '$ffInstall\mozilla.cfg' -Force; " +
            "Copy-Item -LiteralPath '$stage\autoconfig.js' -Destination '$ffInstall\defaults\pref\autoconfig.js' -Force"
    try {
        Invoke-Expression $copy
    } catch {
        # The Firefox folder is usually in Program Files, which needs admin rights.
        Write-Host '  Windows will ask for admin rights to add 2 small files to the Firefox folder.'
        try {
            Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile', '-Command', $copy
        } catch {
            Write-Host '  Admin prompt was declined, the new tab page was not set up.' -ForegroundColor Yellow
        }
    }
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

    if ((Test-Path $cfgPath) -and (Test-Path (Join-Path $ffInstall 'defaults\pref\autoconfig.js'))) {
        Write-Host '  Firefox will open Simple-start for new tabs and on start.'
        Write-Host '  Turn off any new tab extension (like Bonjourr), those take priority.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  All done! Restart Firefox completely.' -ForegroundColor Green
    }
    Write-Host ''
}

Install-HeliumFoxStartPage
