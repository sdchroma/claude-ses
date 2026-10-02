# Claude Code ayarlarına Claude Ses girdilerini ekleme/çıkarma (kur.ps1 ve kaldir.ps1 kullanır)

$script:CSMarkerStart = '<!-- ClaudeSes:start -->'
$script:CSMarkerEnd   = '<!-- ClaudeSes:end -->'

# Eski (~/.claude/hooks/speak.ps1) ve yeni kurulumun komutlarını tanır
function Test-CSCommand([string]$cmd) { return ($cmd -match 'speak\.ps1') }

function ConvertTo-HT($o) {
    if ($null -eq $o) { return $null }
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-HT $p.Value }
        return $h
    }
    if ($o -is [array]) {
        $l = New-Object System.Collections.ArrayList
        foreach ($i in $o) { [void]$l.Add((ConvertTo-HT $i)) }
        return , $l
    }
    return $o
}

function Read-ClaudeSettings([string]$path) {
    if (-not (Test-Path $path)) { return [ordered]@{} }
    $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if (-not $raw.Trim()) { return [ordered]@{} }
    return ConvertTo-HT ($raw | ConvertFrom-Json)
}

function Write-Utf8NoBom([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Remove-CSSettings($s) {
    if ($s.Contains('hooks')) {
        foreach ($event in @($s.hooks.Keys)) {
            $groups = New-Object System.Collections.ArrayList
            foreach ($g in $s.hooks[$event]) {
                $kept = New-Object System.Collections.ArrayList
                foreach ($h in $g.hooks) { if (-not (Test-CSCommand $h.command)) { [void]$kept.Add($h) } }
                if ($kept.Count -gt 0) { $g.hooks = $kept; [void]$groups.Add($g) }
            }
            if ($groups.Count -gt 0) { $s.hooks[$event] = $groups } else { $s.hooks.Remove($event) }
        }
        if ($s.hooks.Count -eq 0) { $s.Remove('hooks') }
    }
    if ($s.Contains('permissions') -and $s.permissions.Contains('allow')) {
        $allow = New-Object System.Collections.ArrayList
        foreach ($r in $s.permissions.allow) { if (-not (Test-CSCommand $r)) { [void]$allow.Add($r) } }
        $s.permissions.allow = $allow
    }
}

function Add-CSSettings($s, [string]$cmd) {
    if (-not $s.Contains('hooks')) { $s.hooks = [ordered]@{} }
    foreach ($event in @('Notification', 'Stop')) {
        if (-not $s.hooks.Contains($event)) { $s.hooks[$event] = New-Object System.Collections.ArrayList }
        $hook = [ordered]@{ type = 'command'; command = "$cmd $event"; async = $true; timeout = 30 }
        [void]$s.hooks[$event].Add([ordered]@{ hooks = @($hook) })
    }
    if (-not $s.Contains('permissions')) { $s.permissions = [ordered]@{} }
    if (-not $s.permissions.Contains('allow')) { $s.permissions.allow = New-Object System.Collections.ArrayList }
    [void]$s.permissions.allow.Add("PowerShell($cmd -Text *)")
    [void]$s.permissions.allow.Add("Bash($cmd -Text *)")
}

function Remove-CSRules([string]$md) {
    $pattern = '(?s)\r?\n?' + [regex]::Escape($CSMarkerStart) + '.*?' + [regex]::Escape($CSMarkerEnd) + '\r?\n?'
    return ($md -replace $pattern, "`n").TrimEnd() + "`n"
}
