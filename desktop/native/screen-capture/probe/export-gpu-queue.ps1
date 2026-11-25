param(
    [Parameter(Mandatory = $true)]
    [string] $TracePath
)

$ErrorActionPreference = 'Stop'
$trace = (Resolve-Path -LiteralPath $TracePath).ProviderPath
$folder = Split-Path -Parent $trace
$csv = Join-Path $folder 'gpu-queue-sample.csv'
$zip = Join-Path $folder 'gpu-queue-sample.zip'

# The provider IDs are present in ETL headers even without display names.
function Get-ProviderFilter([guid] $Id) {
    $lower = $Id.ToString('B')
    $upper = $lower.ToUpperInvariant()
    return "Provider[@Guid='$lower' or @Guid='$upper']"
}

$glitch = Get-ProviderFilter '5cb165ff-eaff-4cf8-9244-55d1adef74e5'
$dxg = Get-ProviderFilter '802ec45a-1e99-4b83-9920-87c98277ba9d'
$first = Get-WinEvent -Path $trace -Oldest -MaxEvents 1 -FilterXPath "*[System[$glitch and EventID=1]]"
$from = $first.TimeCreated.ToUniversalTime().AddSeconds(10)
$start = $from.ToString('o')
$end = $from.AddSeconds(1).ToString('o')
$filter = "*[System[($glitch or $dxg or Provider[@Name='Microsoft-Windows-DxgKrnl']) and TimeCreated[@SystemTime >= '$start' and @SystemTime < '$end']]]"

Get-WinEvent -Path $trace -Oldest -FilterXPath $filter |
    ForEach-Object {
        $record = $_
        $xmlError = $null
        $xml = try { $record.ToXml() } catch { $xmlError = $_.Exception.Message; $null }
        [pscustomobject]@{
            TimeUtc = $record.TimeCreated.ToUniversalTime().ToString('o')
            Provider = $record.ProviderName
            ProviderId = $record.ProviderId
            EventId = $record.Id
            Opcode = $record.Opcode
            ProcessId = $record.ProcessId
            ThreadId = $record.ThreadId
            Xml = $xml
            XmlError = $xmlError
        }
    } | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8

Compress-Archive -LiteralPath $csv -DestinationPath $zip -Force
Get-Item -LiteralPath $zip | Select-Object FullName, Length
