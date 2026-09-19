<#
.SYNOPSIS
    Parse host nominations out of a saved dump of the club sign-up sheet.

.DESCRIPTION
    The Drive connector renders the whole workbook as markdown tables. The
    'Sign Up Here' tab lays each host out as a block:

        | Host 01: | David Mck |
        | Game 1:  | The Networks |
        | Game 2:  | Altiplano |
        | Game 3:  | Yamatai |
        | [merged] Comments: |
        | [merged] <host comment> |

    This script finds those blocks wherever they sit in the dump and emits one
    row per nominated game. It does not touch BGG or the canonical dataset.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SheetDumpPath,

    [Parameter(Mandatory = $true)]
    [string]$OutPath
)

# Compatibility entrypoint; implementation belongs to a system.
& (Join-Path $PSScriptRoot '../../../../systems/prediction/club-nominations/Parse-Nominations.ps1') @PSBoundParameters
