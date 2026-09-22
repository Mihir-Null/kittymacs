param([string]$Link, [string]$Target, [string]$Fixture)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($Fixture).TrimEnd('\') + '\'
$linkPath = [IO.Path]::GetFullPath($Link)
$targetPath = [IO.Path]::GetFullPath($Target)
if (-not $linkPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or
    -not $targetPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Retarget paths must be inside the explicit test fixture'
}
if ((Split-Path -Leaf $linkPath) -ne 'retarget') { throw 'Only the retarget test junction may change' }
if ((Get-Item -LiteralPath $linkPath).LinkType -ne 'Junction') { throw 'Expected a junction' }
# Nonrecursive removal unlinks this exact test junction, never its target.
Remove-Item -LiteralPath $linkPath
New-Item -ItemType Junction -Path $linkPath -Target $targetPath | Out-Null
