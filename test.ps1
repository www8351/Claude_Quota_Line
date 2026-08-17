# Renders statusline.ps1 with a sample payload. No network call is made
# unless a credentials file exists; pass -NoApi to disable the model bucket.
param([switch]$NoApi)
$now = [DateTimeOffset]::Now
$sample = @{
    model          = @{ display_name = 'Claude Fable 5' }
    context_window = @{ used_percentage = 22.4 }
    rate_limits    = @{
        five_hour = @{ used_percentage = 11; resets_at = $now.AddHours(4).AddMinutes(48).ToUnixTimeSeconds() }
        seven_day = @{ used_percentage = 28; resets_at = $now.AddDays(3).ToUnixTimeSeconds() }
    }
} | ConvertTo-Json -Depth 5
$extra = @{ InputJson = $sample }
if ($NoApi) { $extra.ModelKey = '' }
& (Join-Path $PSScriptRoot 'statusline.ps1') @extra