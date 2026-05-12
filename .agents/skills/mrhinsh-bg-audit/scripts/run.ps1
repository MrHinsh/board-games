[CmdletBinding()]
param(
	[string]$Username,
	[string]$Endpoint = 'https://boardgamegeek.com',
	[string]$Cookie,
	[string]$SessionFile = '.\.local\secrets\bgg-session.json',
	[string]$ReportPath = '.\data\reports\quality\duplicate-collection-report.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-ToCookieMap {
	param([object]$InputObject)

	$map = [ordered]@{}
	if ($null -eq $InputObject) {
		return $map
	}

	if ($InputObject -is [System.Collections.IDictionary]) {
		foreach ($key in $InputObject.Keys) {
			if ($null -ne $key) {
				$map[[string]$key] = [string]$InputObject[$key]
			}
		}

		return $map
	}

	foreach ($property in $InputObject.PSObject.Properties) {
		if ($null -ne $property.Value) {
			$map[$property.Name] = [string]$property.Value
		}
	}

	return $map
}

function Build-BggCookieHeader {
	param([object]$CookieMap)

	$resolvedCookieMap = Convert-ToCookieMap -InputObject $CookieMap
	if ($resolvedCookieMap.Count -eq 0) {
		return $null
	}

	$segments = New-Object System.Collections.Generic.List[string]
	foreach ($name in @('SessionID', 'bggusername', 'bggpassword')) {
		if ($resolvedCookieMap.Contains($name) -and $resolvedCookieMap[$name]) {
			$segments.Add("$name=$($resolvedCookieMap[$name])")
		}
	}

	foreach ($entry in $resolvedCookieMap.GetEnumerator()) {
		if ($entry.Key -in @('SessionID', 'bggusername', 'bggpassword')) {
			continue
		}

		if ($entry.Value) {
			$segments.Add("$($entry.Key)=$($entry.Value)")
		}
	}

	return ($segments -join '; ')
}

function Get-SessionCookieHeader {
	param([object]$SessionRecord)

	if ($null -eq $SessionRecord) {
		return $null
	}

	if ($SessionRecord.PSObject.Properties.Name -contains 'cookies') {
		$cookieHeader = Build-BggCookieHeader -CookieMap $SessionRecord.cookies
		if ($cookieHeader) {
			return $cookieHeader
		}
	}

	if ($SessionRecord.PSObject.Properties.Name -contains 'cookie' -and $SessionRecord.cookie) {
		return ([string]$SessionRecord.cookie).Trim()
	}

	return $null
}

function Resolve-BggCookie {
	param(
		[string]$Cookie,
		[string]$SessionFile
	)

	if ($Cookie) {
		return $Cookie.Trim()
	}

	if (Test-Path $SessionFile) {
		$cached = Get-Content -Path $SessionFile -Raw | ConvertFrom-Json
		$cachedCookie = Get-SessionCookieHeader -SessionRecord $cached
		if ($cachedCookie) {
			return $cachedCookie
		}
	}

	if ($env:BGG_COOKIE) {
		return ([string]$env:BGG_COOKIE).Trim()
	}

	throw "No BGG cookie found. Run .\Login-Bgg.ps1 first to populate $SessionFile."
}

function Resolve-BggUsername {
	param(
		[string]$Username,
		[string]$SessionFile
	)

	if ($Username) {
		return $Username
	}

	if (Test-Path $SessionFile) {
		$cached = Get-Content -Path $SessionFile -Raw | ConvertFrom-Json
		if ($cached.username) {
			return [string]$cached.username
		}
	}

	if ($env:BGG_USERNAME) {
		return [string]$env:BGG_USERNAME
	}

	throw 'No BGG username found. Provide -Username or run .\Login-Bgg.ps1 first.'
}

function Get-CollectionName {
	param([object]$Item)

	if ($null -eq $Item) {
		return ''
	}

	$nameNode = $Item.name
	if ($nameNode -is [System.Array]) {
		$first = $nameNode | Select-Object -First 1
		if ($null -ne $first) {
			return [string]$first.InnerText
		}
	}

	if ($null -ne $nameNode) {
		return [string]$nameNode.InnerText
	}

	return ''
}

function Get-CollectionRatingText {
	param([object]$Item)

	if ($null -eq $Item -or $null -eq $Item.stats -or $null -eq $Item.stats.rating) {
		return 'N/A'
	}

	$value = [string]$Item.stats.rating.value
	if ([string]::IsNullOrWhiteSpace($value)) {
		return 'N/A'
	}

	return $value
}

$cookieString = Resolve-BggCookie -Cookie $Cookie -SessionFile $SessionFile
$effectiveUsername = Resolve-BggUsername -Username $Username -SessionFile $SessionFile

$uri = "$Endpoint/xmlapi2/collection?username=$([uri]::EscapeDataString($effectiveUsername))&own=1&stats=1"
$headers = @{ Cookie = $cookieString }

$response = $null
for ($attempt = 0; $attempt -lt 6; $attempt++) {
	$response = Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 60
	if ($response.StatusCode -eq 202) {
		continue
	}

	break
}

if ($null -eq $response -or $response.StatusCode -ne 200) {
	throw "Collection fetch failed with HTTP $($response.StatusCode)."
}

[xml]$xml = $response.Content
$items = @($xml.items.item)
$duplicates = @($items | Group-Object { [int]$_.objectid } | Where-Object { $_.Count -gt 1 } | Sort-Object Name)

$reportEntries = foreach ($group in $duplicates) {
	$groupItems = @($group.Group)
	$ratings = @($groupItems | ForEach-Object { Get-CollectionRatingText -Item $_ })
	[pscustomobject]@{
		bgg_id = [int]$group.Name
		name = Get-CollectionName -Item $groupItems[0]
		copies = $groupItems.Count
		collids = @($groupItems | ForEach-Object { [int]$_.collid })
		ratings = $ratings
		unique_ratings = @($ratings | Select-Object -Unique)
		ratings_match = (@($ratings | Select-Object -Unique).Count -eq 1)
	}
}

$report = [pscustomobject]@{
	run_at = (Get-Date -Format 'o')
	username = $effectiveUsername
	duplicate_count = $reportEntries.Count
	duplicates = @($reportEntries)
}

$reportDir = Split-Path -Path $ReportPath -Parent
if ($reportDir -and -not (Test-Path $reportDir)) {
	New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 10 | Set-Content -Path $ReportPath -Encoding UTF8

[pscustomobject]@{
	ReportPath = $ReportPath
	DuplicateCount = $reportEntries.Count
	MismatchedRatings = @($reportEntries | Where-Object { -not $_.ratings_match }).Count
}
