<#
.SYNOPSIS
  Acquires a create-only GitHub claim label for one open REA issue.
.DESCRIPTION
  Use an attempt ID unique to your AI session, such as R16-Ada-01. Read the
  issue and its dependencies first. Once created, the label is the claim even
  if issue synchronization fails. Only coordination can archive and free it.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, 2147483647)][int]$Issue,
    [Parameter(Mandatory)][ValidatePattern('^R[0-9]{2,}-[A-Za-z][A-Za-z0-9]{1,23}-[0-9]{2,}$')][string]$Attempt,
    [Parameter(Mandatory)][ValidatePattern('^[^\r\n]{1,240}$')][string]$Build,
    [Parameter(Mandatory)][ValidatePattern('^[^\r\n]{1,320}$')][string]$Scope
)

$ErrorActionPreference = 'Stop'
$repo = 'lucaseddd/victory-rea'
$Attempt = $Attempt.Substring(0, $Attempt.IndexOf('-')).ToUpperInvariant() + $Attempt.Substring($Attempt.IndexOf('-'))
$task = $Attempt.Split('-')[0]
$claim = "claim:$task"
$raw = gh issue view $Issue --repo $repo --json title,state,labels,url
if ($LASTEXITCODE -ne 0) { throw "Could not read issue #$Issue." }
$entry = $raw | ConvertFrom-Json
if ($entry.state -ne 'OPEN' -or $entry.title -notmatch ('^\[' + $task + '\]') -or
    $entry.labels.name -notcontains 'task' -or $entry.labels.name -notcontains 'status:open') {
    throw "Issue #$Issue is not the open, available $task task."
}
if ($entry.labels.name -contains $claim) { throw "Issue #$Issue already has $claim." }

$created = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
$body = @(
    "claim: $Attempt"
    "claimed at: $created"
    "build: $Build"
    "scope: $Scope"
    'progress: 0%'
) -join [Environment]::NewLine
$temp = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($temp, $body, [Text.UTF8Encoding]::new($false))
    gh label create $claim --repo $repo --color 5319e7 --description "$Attempt | issue #$Issue | $created"
    if ($LASTEXITCODE -ne 0) {
        throw "Claim not acquired. Check $claim in GitHub labels and choose another task if occupied."
    }
    gh issue edit $Issue --repo $repo --add-label $claim --add-label 'status:in-progress' --remove-label 'status:open'
    if ($LASTEXITCODE -ne 0) {
        throw "Acquired $claim for $Attempt. Keep the claim and ask R00 to attach it to issue #$Issue."
    }
    gh issue comment $Issue --repo $repo --body-file $temp
    if ($LASTEXITCODE -ne 0) {
        throw "Acquired and attached $claim for $Attempt. Add the claim comment manually to issue #$Issue."
    }
    Write-Output "Claim acquired for $Attempt. $($entry.url)"
} finally {
    [IO.File]::Delete($temp)
}
