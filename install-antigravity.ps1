# Islands Dark Theme Installer for Antigravity
# Antigravity is a VS Code-compatible IDE with its own CLI and extensions dir.

param()

$ErrorActionPreference = "Stop"

Write-Host "Islands Dark Theme Installer for Antigravity" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$packageFile = Join-Path $scriptDir "package.json"
$package = Get-Content $packageFile -Raw | ConvertFrom-Json
$extensionId = "$($package.publisher).$($package.name)"
$extensionFolderName = "$extensionId-$($package.version)"

function Find-AntigravityCli {
    $command = Get-Command "antigravity" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $possiblePaths = @(
        "$env:LOCALAPPDATA\Programs\Antigravity\bin\antigravity.cmd",
        "$env:LOCALAPPDATA\Programs\Antigravity\bin\antigravity.exe",
        "$env:ProgramFiles\Antigravity\bin\antigravity.cmd",
        "${env:ProgramFiles(x86)}\Antigravity\bin\antigravity.cmd"
    )

    foreach ($path in $possiblePaths) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }

    return $null
}

function Invoke-CommandChecked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = $scriptDir
    )

    Push-Location $WorkingDirectory
    try {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        $hasNativePreference = Test-Path Variable:\PSNativeCommandUseErrorActionPreference
        if ($hasNativePreference) {
            $previousNativePreference = $PSNativeCommandUseErrorActionPreference
            $PSNativeCommandUseErrorActionPreference = $false
        }

        try {
            $output = & $Command @Arguments 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            if ($hasNativePreference) {
                $PSNativeCommandUseErrorActionPreference = $previousNativePreference
            }
            $ErrorActionPreference = $previousErrorActionPreference
        }

        $output | ForEach-Object {
            Write-Host $_
        }

        if ($exitCode -ne 0) {
            throw "Command failed with exit code $exitCode`: $Command $($Arguments -join ' ')"
        }
    } finally {
        Pop-Location
    }
}

function New-IslandsVsix {
    $npx = Get-Command "npx.cmd" -ErrorAction SilentlyContinue
    if (-not $npx) {
        $npx = Get-Command "npx" -ErrorAction SilentlyContinue
    }

    if (-not $npx) {
        return $null
    }

    $distDir = Join-Path $scriptDir "dist"
    if (-not (Test-Path $distDir)) {
        New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    }

    $vsixPath = Join-Path $distDir "$($package.name)-$($package.version).vsix"
    if (Test-Path $vsixPath) {
        Remove-Item -LiteralPath $vsixPath -Force
    }

    Write-Host "   Packaging $extensionId@$($package.version) as VSIX..."
    Invoke-CommandChecked -Command $npx.Source -Arguments @("--yes", "@vscode/vsce", "package", "--out", $vsixPath)

    if (Test-Path $vsixPath) {
        return $vsixPath
    }

    return $null
}

function Install-ThemeByCopyFallback {
    Write-Host "   VSIX packaging unavailable; copying extension files directly." -ForegroundColor Yellow

    $extensionsDir = "$env:USERPROFILE\.antigravity\extensions"
    $targetDir = Join-Path $extensionsDir $extensionFolderName

    if (Test-Path $targetDir) {
        Remove-Item -LiteralPath $targetDir -Recurse -Force
    }

    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Copy-Item (Join-Path $scriptDir "package.json") $targetDir -Force
    Copy-Item (Join-Path $scriptDir "README.md") $targetDir -Force
    Copy-Item (Join-Path $scriptDir "themes") (Join-Path $targetDir "themes") -Recurse -Force

    $extensionsJson = Join-Path $extensionsDir "extensions.json"
    if (Test-Path $extensionsJson) {
        Remove-Item -LiteralPath $extensionsJson -Force
    }

    return $targetDir
}

$antigravityDir = "$env:USERPROFILE\.gemini\antigravity"
$antigravityUserDir = "$env:APPDATA\Antigravity"
$antigravityExtensionsDir = "$env:USERPROFILE\.antigravity\extensions"

if (-not ((Test-Path $antigravityDir) -or (Test-Path $antigravityUserDir) -or (Test-Path $antigravityExtensionsDir))) {
    Write-Host "Error: Antigravity was not found." -ForegroundColor Red
    Write-Host "Please install and run Antigravity at least once before using this installer."
    exit 1
}

$antigravityCli = Find-AntigravityCli
if ($antigravityCli) {
    Write-Host "Antigravity CLI found: $antigravityCli" -ForegroundColor Green
} else {
    Write-Host "Antigravity CLI was not found; direct extension copy will be used." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 1: Installing Islands Dark theme extension..."

$installedByVsix = $false
if ($antigravityCli) {
    try {
        $vsixPath = New-IslandsVsix
        if ($vsixPath) {
            Invoke-CommandChecked -Command $antigravityCli -Arguments @("--install-extension", $vsixPath, "--force")
            $installedByVsix = $true
            Write-Host "Theme extension installed with Antigravity CLI" -ForegroundColor Green
        }
    } catch {
        Write-Host "Could not install with VSIX: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if (-not $installedByVsix) {
    $targetDir = Install-ThemeByCopyFallback
    Write-Host "Theme extension installed to $targetDir" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 2: Installing Custom UI Style extension..."
if ($antigravityCli) {
    try {
        Invoke-CommandChecked -Command $antigravityCli -Arguments @("--install-extension", "subframe7536.custom-ui-style", "--force")
        Write-Host "Custom UI Style extension installed in Antigravity" -ForegroundColor Green
    } catch {
        Write-Host "Could not install Custom UI Style automatically in Antigravity" -ForegroundColor Yellow
        Write-Host "   Install it manually in Antigravity if CSS customizations do not apply."
    }
} else {
    Write-Host "Could not install Custom UI Style automatically without the Antigravity CLI" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Step 3: Installing Bear Sans UI fonts..."
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"

if (-not (Test-Path $fontDir)) {
    New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
}

try {
    $fonts = Get-ChildItem "$scriptDir\fonts\*.otf"
    foreach ($font in $fonts) {
        try {
            Copy-Item $font.FullName $fontDir -Force -ErrorAction SilentlyContinue
        } catch {
            # Continue if a font is already installed or locked.
        }
    }

    Write-Host "Fonts installed" -ForegroundColor Green
    Write-Host "   Note: You may need to restart applications to use the new fonts" -ForegroundColor DarkGray
} catch {
    Write-Host "Could not install fonts automatically" -ForegroundColor Yellow
    Write-Host "   Please manually install the fonts from the 'fonts/' folder"
    Write-Host "   Select all .otf files and right-click > Install"
}

Write-Host ""
Write-Host "Step 4: Applying Antigravity settings..."

$settingsDir = "$env:APPDATA\Antigravity\User"
$settingsFile = "$settingsDir\settings.json"

if (-not (Test-Path $settingsDir)) {
    Write-Host "Creating Antigravity settings directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}

function Strip-Jsonc {
    param([string]$Text)
    $Text = $Text -replace '(?m)^\s*//.*$', ''
    $Text = $Text -replace '/\*[\s\S]*?\*/', ''
    $Text = $Text -replace ',\s*([}\]])', '$1'
    return $Text
}

$newSettingsRaw = Get-Content "$scriptDir\settings.json" -Raw
$newSettings = (Strip-Jsonc $newSettingsRaw) | ConvertFrom-Json

if (Test-Path $settingsFile) {
    Write-Host "Existing settings.json found at: $settingsFile" -ForegroundColor Yellow
    Write-Host "   Backing up to settings.json.backup"
    Copy-Item $settingsFile "$settingsFile.backup" -Force

    try {
        $existingRaw = Get-Content $settingsFile -Raw
        $existingSettings = (Strip-Jsonc $existingRaw) | ConvertFrom-Json

        $mergedSettings = @{}
        $existingSettings.PSObject.Properties | ForEach-Object {
            $mergedSettings[$_.Name] = $_.Value
        }
        $newSettings.PSObject.Properties | ForEach-Object {
            $mergedSettings[$_.Name] = $_.Value
        }

        $stylesheetKey = 'custom-ui-style.stylesheet'
        if ($existingSettings.$stylesheetKey -and $newSettings.$stylesheetKey) {
            $mergedStylesheet = @{}
            $existingSettings.$stylesheetKey.PSObject.Properties | ForEach-Object {
                $mergedStylesheet[$_.Name] = $_.Value
            }
            $newSettings.$stylesheetKey.PSObject.Properties | ForEach-Object {
                $mergedStylesheet[$_.Name] = $_.Value
            }
            $mergedSettings[$stylesheetKey] = [PSCustomObject]$mergedStylesheet
        }

        [PSCustomObject]$mergedSettings | ConvertTo-Json -Depth 100 | Set-Content $settingsFile
        Write-Host "Settings merged successfully" -ForegroundColor Green
    } catch {
        Write-Host "Could not merge settings automatically" -ForegroundColor Yellow
        Write-Host "   Please manually merge settings.json from this repo into your Antigravity settings"
        Write-Host "   Your original settings have been backed up to settings.json.backup"
    }
} else {
    Copy-Item "$scriptDir\settings.json" $settingsFile
    Write-Host "Settings applied to: $settingsFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 5: Enabling Custom UI Style..."

$firstRunFile = Join-Path $scriptDir ".islands_dark_first_run_antigravity"
if (-not (Test-Path $firstRunFile)) {
    New-Item -ItemType File -Path $firstRunFile | Out-Null
    Write-Host ""
    Write-Host "Important Notes:" -ForegroundColor Yellow
    Write-Host "   - IBM Plex Mono and FiraCode Nerd Font Mono need to be installed separately"
    Write-Host "   - After Antigravity reloads, you may see a 'corrupt installation' warning"
    Write-Host "   - This is expected when using custom CSS - click the gear icon and select 'Don't Show Again'"
    Write-Host "   - To activate the theme in Antigravity, use the theme picker (Cmd/Ctrl+K Cmd/Ctrl+T)"
    Write-Host ""
    Read-Host "Press Enter to continue"
}

Write-Host "   Applying CSS customizations..."

Write-Host ""
Write-Host "Islands Dark theme has been installed for Antigravity!" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "   1. Restart Antigravity to apply the changes"
Write-Host "   2. Open the Command Palette (Cmd/Ctrl+Shift+P)"
Write-Host "   3. Type 'Color Theme' and select 'Preferences: Color Theme'"
Write-Host "   4. Select 'Islands Dark' from the list"
Write-Host "   5. If you see a warning about corrupt installation, click 'Don't Show Again'"
Write-Host ""

Write-Host "Settings file location: $settingsFile" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host ""

Start-Sleep -Seconds 3
