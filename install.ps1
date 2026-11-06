# HeliumFox installer
# Usage: irm https://raw.githubusercontent.com/rs4t/heliumfox/main/install.ps1 | iex

function Install-HeliumFox {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo = 'https://raw.githubusercontent.com/rs4t/heliumfox/main'
    $utf8 = New-Object Text.UTF8Encoding $false

    # Settings HeliumFox needs. Latin Accent Plus' see-through settings are switched off.
    $prefs = [ordered]@{
        'toolkit.legacyUserProfileCustomizations.stylesheets'          = 'true'
        'browser.tabs.inTitlebar'                                      = '1'
        'browser.tabs.allow_transparent_browser'                       = 'false'
        'widget.windows.mica'                                          = 'false'
        'gfx.webrender.all'                                            = 'true'
        'widget.non-native-theme.scrollbar.style'                      = '5'
        'widget.windows.overlay-scrollbars.enabled'                    = 'true'
        'widget.non-native-theme.win11.scrollbar.force-overlay-style'  = 'true'
    }

    Write-Host ''
    Write-Host '  HeliumFox installer' -ForegroundColor Cyan
    Write-Host ''

    # ---- Find the Firefox profile ------------------------------------------
    $ffDir = Join-Path $env:APPDATA 'Mozilla\Firefox'
    if ($env:HELIUMFOX_PROFILE) {
        $profiles = @($env:HELIUMFOX_PROFILE)
    } else {
        $ini = Join-Path $ffDir 'profiles.ini'
        if (-not (Test-Path $ini)) {
            Write-Host '  Could not find Firefox. Open Firefox once, close it, then run this again.' -ForegroundColor Red
            return
        }
        $sections = @{}
        $current = $null
        foreach ($line in Get-Content $ini) {
            if ($line -match '^\[(.+)\]\s*$') {
                $current = $Matches[1]
                $sections[$current] = @{}
            } elseif ($current -and $line -match '^([^=]+)=(.*)$') {
                $sections[$current][$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
        # The [Install...] sections hold the profile each Firefox install really uses;
        # the Default=1 flag on [Profile...] sections is often stale.
        $candidates = @($sections.Keys | Where-Object { $_ -like 'Install*' } |
            ForEach-Object { $sections[$_]['Default'] } | Where-Object { $_ })
        if (-not $candidates) {
            $candidates = @($sections.Values | Where-Object { $_['Default'] -eq '1' -and $_['Path'] } |
                ForEach-Object { $_['Path'] })
        }
        $profiles = @($candidates | ForEach-Object {
            if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $ffDir ($_ -replace '/', '\') }
        } | Where-Object { Test-Path $_ } | Select-Object -Unique)
    }

    if ($profiles.Count -eq 0) {
        Write-Host '  Could not find your Firefox profile folder.' -ForegroundColor Red
        return
    }
    $profileDir = $profiles[0]
    if ($profiles.Count -gt 1) {
        Write-Host '  Found more than one Firefox profile:'
        for ($i = 0; $i -lt $profiles.Count; $i++) {
            Write-Host "    [$($i + 1)] $($profiles[$i])"
        }
        $choice = Read-Host '  Which one do you want to install to? (number)'
        $index = 0
        if (-not [int]::TryParse($choice, [ref]$index) -or $index -lt 1 -or $index -gt $profiles.Count) {
            Write-Host '  Invalid choice, nothing was changed.' -ForegroundColor Red
            return
        }
        $profileDir = $profiles[$index - 1]
    }
    Write-Host "  Profile: $profileDir"

    # ---- Theme files ---------------------------------------------------------
    $chromeDir = Join-Path $profileDir 'chrome'
    New-Item -ItemType Directory -Force -Path $chromeDir | Out-Null

    # The theme lives in its own files; userChrome.css / userContent.css only
    # import them. Other CSS add-ons imported there (like Firefox Compact) are
    # kept. Latin Accent Plus' import is removed, since both themes style the
    # same things.
    $themeFiles = [ordered]@{
        'userChrome.css'  = 'heliumfox.css'
        'userContent.css' = 'heliumfox-content.css'
    }
    foreach ($entry in $themeFiles.GetEnumerator()) {
        Invoke-WebRequest -UseBasicParsing -Uri "$repo/chrome/$($entry.Value)" -OutFile (Join-Path $chromeDir $entry.Value)
    }
    Write-Host '  Downloaded the theme files.'

    $backupDir = Join-Path $chromeDir ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $keptImports = @()
    $removedLatin = $false
    foreach ($entry in $themeFiles.GetEnumerator()) {
        $path = Join-Path $chromeDir $entry.Key
        $otherImports = @()
        if (Test-Path $path) {
            $lines = [IO.File]::ReadAllLines($path, $utf8)
            foreach ($l in $lines) {
                if ($l -notmatch '^\s*@import\s') { continue }
                if ($l -match [regex]::Escape($entry.Value)) { continue }
                if ($l -match 'latin-accent-plus') { $removedLatin = $true; continue }
                $otherImports += $l
            }
            # Anything besides @import lines (or a removed Latin Accent Plus import)
            # is another theme that gets replaced - keep a backup first.
            if ($removedLatin -or @($lines | Where-Object { $_.Trim() -and $_ -notmatch '^\s*@import\s' }).Count -gt 0) {
                New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
                Copy-Item $path $backupDir
            }
        }
        $keptImports += $otherImports
        # Other imports (e.g. Firefox Compact's compact.css) stay first.
        $text = (($otherImports + @("@import `"$($entry.Value)`";")) -join "`r`n") + "`r`n"
        [IO.File]::WriteAllText($path, $text, $utf8)
    }
    if (Test-Path $backupDir) {
        Write-Host "  Backed up your old theme files to: $backupDir"
    }
    if ($removedLatin) {
        Write-Host '  Switched off Latin Accent Plus (its files are still there if you want it back).'
    }
    if ($keptImports) {
        Write-Host "  Kept your other CSS imports: $((($keptImports | ForEach-Object { $_.Trim() }) | Select-Object -Unique) -join ', ')"
    }

    # ---- Settings (user.js) --------------------------------------------------
    $userJs = Join-Path $profileDir 'user.js'
    $existing = @()
    if (Test-Path $userJs) { $existing = [IO.File]::ReadAllLines($userJs, $utf8) }
    $names = @($prefs.Keys)
    $keep = @($existing | Where-Object {
        $line = $_
        -not ($names | Where-Object { $line -match ('user_pref\("' + [regex]::Escape($_) + '"') }) -and
        $line -notmatch '^// HeliumFox'
    })
    $block = @('', '// HeliumFox') + ($prefs.GetEnumerator() | ForEach-Object { "user_pref(`"$($_.Key)`", $($_.Value));" })
    [IO.File]::WriteAllText($userJs, ((($keep + $block) -join "`r`n").Trim() + "`r`n"), $utf8)
    Write-Host '  Set the Firefox settings HeliumFox needs.'

    # ---- Toolbar layout like Helium (needs Firefox closed) -------------------
    $prefsJs = Join-Path $profileDir 'prefs.js'
    $ffRunning = { [bool](Get-Process firefox -ErrorAction SilentlyContinue) }
    if (-not $env:HELIUMFOX_PROFILE -and (& $ffRunning)) {
        Write-Host ''
        Write-Host '  Firefox is open. Close it to also arrange the toolbar like Helium,' -ForegroundColor Yellow
        $answer = Read-Host '  then press Enter (or type S and Enter to skip)'
        if ($answer -match '^\s*s') { $prefsJs = $null }
        elseif (& $ffRunning) {
            Write-Host '  Firefox is still open, skipping the toolbar layout.' -ForegroundColor Yellow
            $prefsJs = $null
        }
    }
    $layoutDone = $false
    if ($prefsJs -and (Test-Path $prefsJs)) {
        $src = [IO.File]::ReadAllText($prefsJs, $utf8)
        $m = [regex]::Match($src, '(?m)^user_pref\("browser\.uiCustomization\.state", "(.*)"\);\r?$')
        if ($m.Success) {
            Copy-Item $prefsJs ($prefsJs + '.heliumfox-backup') -Force
            $state = ('"' + $m.Groups[1].Value + '"' | ConvertFrom-Json) | ConvertFrom-Json
            $p = $state.placements
            $ext = @($p.'nav-bar' | Where-Object { $_ -like '*-browser-action' })
            $p.'nav-bar' = @('back-button', 'forward-button', 'stop-reload-button', 'urlbar-container',
                             'vertical-spacer', 'new-tab-button') + $ext + @('downloads-button', 'unified-extensions-button')
            $p.TabsToolbar = @('tabbrowser-tabs')
            foreach ($w in 'sidebar-button', 'firefox-view-button', 'new-tab-button') {
                if (@($state.seen) -notcontains $w) { $state.seen = @($state.seen) + $w }
            }
            $json = $state | ConvertTo-Json -Compress -Depth 20
            $encoded = ($json | ConvertTo-Json -Compress)
            $encoded = $encoded.Substring(1, $encoded.Length - 2)
            $src = $src.Substring(0, $m.Groups[1].Index) + $encoded + $src.Substring($m.Groups[1].Index + $m.Groups[1].Length)
            [IO.File]::WriteAllText($prefsJs, $src, $utf8)
            $layoutDone = $true
            Write-Host '  Arranged the toolbar like Helium (old settings saved as prefs.js.heliumfox-backup).'
        }
    }
    if (-not $layoutDone) {
        Write-Host '  Toolbar not arranged: right-click the toolbar > Customize Toolbar and move the + button' -ForegroundColor Yellow
        Write-Host '  next to the address bar (see the README).' -ForegroundColor Yellow
    }

    Write-Host ''
    if (& $ffRunning) {
        Write-Host '  Done! Close Firefox completely and open it again to see HeliumFox.' -ForegroundColor Green
    } else {
        Write-Host '  Done! Open Firefox to see HeliumFox.' -ForegroundColor Green
    }
    Write-Host ''
}

Install-HeliumFox
