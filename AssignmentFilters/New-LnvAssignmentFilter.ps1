<#
.SYNOPSIS
    Creates Intune assignment filters for Lenovo models using the Lenovo model catalog.

.DESCRIPTION
    Intune reports the machine type model (for example 21N1CTO1WW) in the device model property
    for Lenovo hardware rather than the marketing name, which makes model based assignment
    filters tedious to create.

    This script downloads the Lenovo model catalog, collapses the catalog entries down to
    friendly model names, and builds one Intune assignment filter per model whose rule
    matches every machine type prefix belonging to that model.

    A single marketing name is spread across several catalog entries that carry a
    "Type XXXX YYYY" suffix. ThinkPad T14S Gen 6, for example, is five separate catalog
    entries covering ten machine types. The suffix is stripped and the machine types are
    merged so one filter covers the whole model.

.PARAMETER Model
    One or more friendly model names to create filters for. Wildcards are supported, so
    'ThinkPad T14*' matches every T14 variant in the catalog. When omitted, every model in
    the catalog is selected, which is rarely what you want - run -ListAvailable first.

    The brand word is optional, so 'T14 Gen 6' matches 'ThinkPad T14 Gen 6' and
    'M70Q Gen 5' matches 'ThinkCentre M70Q Gen 5'. Matching is case insensitive. The
    created filter is always named from the full catalog name regardless of how it was
    matched. Each pattern is reported separately, so one that matches nothing raises a
    warning rather than discarding the rest of the run.

.PARAMETER MachineType
    One or more machine types to look the model up by, for the case where the machine type
    is known but the marketing name is not. Accepts the bare machine type ('21N1') or the
    full model string as Intune reports it ('21N1CTO1WW'), which can be pasted straight out
    of the portal. Only the first four characters are significant.

    Wildcards are supported and are expanded against the catalog, so '21L*' resolves to
    every 21L machine type that exists and selects each model those belong to. A wildcard
    value is matched whole rather than truncated, so '21*' is valid where a literal value
    would need four characters.

    A machine type selects the whole model it belongs to, so the filter that gets created
    covers every sibling machine type rather than only the one supplied. Looking up 21N1
    produces the complete ThinkPad T14S Gen 6 filter covering all ten of its machine types.

    Cannot be combined with -Model.

.PARAMETER ListAvailable
    Outputs the friendly model names and their machine types without contacting Graph.
    Nothing is created. Use this to scope the -Model or -MachineType value.

.PARAMETER SplitByArchitecture
    Creates a separate filter per processor architecture instead of one filter per model.
    Several models ship on more than one architecture - ThinkPad T14S Gen 6 spans Intel,
    AMD and Qualcomm - and driver or firmware targeting often needs them kept apart. The
    architecture is appended to the filter name, for example
    "Lenovo - ThinkPad T14S Gen 6 (Intel)".

.PARAMETER NamePrefix
    Text prepended to every filter display name. Defaults to 'Lenovo - '. Pass an empty
    string to use the bare model name.

.PARAMETER GraphApiVersion
    Graph endpoint to call. Defaults to 'beta'.

.PARAMETER Force
    Updates the rule on a filter that already exists with the same display name. Without
    this switch an existing filter is left untouched and reported as Skipped.

.EXAMPLE
    .\New-LnvAssignmentFilter.ps1 -ListAvailable

    Lists every friendly model name and its machine types. Nothing is created.

.EXAMPLE
    .\New-LnvAssignmentFilter.ps1 -Model 'ThinkPad T14S Gen 6' -WhatIf

    Shows the filter that would be created for the T14s Gen 6 without writing to Intune.

.EXAMPLE
    .\New-LnvAssignmentFilter.ps1 -Model 'T14 Gen 6'

    Creates a filter for ThinkPad T14 Gen 6. The brand word is optional when matching.

.EXAMPLE
    .\New-LnvAssignmentFilter.ps1 -MachineType '21N1' -ListAvailable

    Identifies which model machine type 21N1 belongs to without creating anything.

.EXAMPLE
    .\New-LnvAssignmentFilter.ps1 -MachineType '21L*' -ListAvailable -Verbose

    Expands the wildcard against the catalog and lists every model holding a 21L machine
    type. Verbose output reports what the wildcard expanded to.

.EXAMPLE
    .\New-LnvAssignmentFilter.ps1 -MachineType '21N1CTO1WW'

    Creates the filter for the model that machine type belongs to, using a device.model
    value pasted straight from the Intune portal.

.EXAMPLE
    .\New-LnvAssignmentFilter.ps1 -Model 'ThinkPad X1 Carbon*', 'ThinkPad T14*'

    Creates a filter for every X1 Carbon and T14 model in the catalog.

.EXAMPLE
    .\New-LnvAssignmentFilter.ps1 -Model 'ThinkPad T14S Gen 6' -SplitByArchitecture

    Creates three filters - Intel, AMD and Qualcomm - for the T14s Gen 6.

.NOTES
    Author : Philip Jorgensen
    Catalog: https://download.lenovo.com/cdrt/td/catalogv2.xml

    Requires the Microsoft.Graph.Authentication module and the
    DeviceManagementConfiguration.ReadWrite.All permission.
#>
#requires -Version 7.0
#requires -Module Microsoft.Graph.Authentication

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Model')]
param(
    [Parameter(ParameterSetName = 'Model')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Model,

    [Parameter(ParameterSetName = 'MachineType')]
    [ValidateNotNullOrEmpty()]
    [string[]]$MachineType,

    [Parameter()]
    [switch]$ListAvailable,

    [Parameter()]
    [switch]$SplitByArchitecture,

    [Parameter()]
    [AllowEmptyString()]
    [string]$NamePrefix = 'Lenovo - ',

    [Parameter()]
    [ValidateSet('beta', 'v1.0')]
    [string]$GraphApiVersion = 'beta',

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Intune caps an assignment filter rule at 3072 characters.
$script:MaxRuleLength = 3072

# The published Lenovo model catalog. There is no alternate source for this data.
$script:CatalogUri = 'https://download.lenovo.com/cdrt/td/catalogv2.xml'

function Get-LnvModelCatalog
{
    <#
    .SYNOPSIS
        Downloads the Lenovo model catalog and groups machine types by friendly model name.
    .PARAMETER PerArchitecture
        Keeps architectures separate instead of merging them into one entry per model.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter()]
        [switch]$PerArchitecture
    )

    Write-Verbose "Downloading Lenovo model catalog from $script:CatalogUri"
    try
    {
        $response = Invoke-WebRequest -Uri $script:CatalogUri -UseBasicParsing
    }
    catch
    {
        throw "Unable to download the Lenovo model catalog from '$script:CatalogUri': $_"
    }

    # The published catalog carries a UTF-8 byte order mark that the XML parser rejects.
    $content = ([string]$response.Content).TrimStart([char]0xFEFF)

    $catalog = New-Object -TypeName System.Xml.XmlDocument
    try
    {
        $catalog.LoadXml($content)
    }
    catch
    {
        throw "The response from '$script:CatalogUri' is not valid XML: $_"
    }

    # Catalog names append a machine type suffix - "ThinkPad T14S Gen 6 Type 21N1 21N2".
    # Strip it so every entry for a model collapses onto the friendly name.
    $typeSuffix = '^(?<Name>.+?)\s+Type\s+[0-9A-Za-z]{4}(?:\s+[0-9A-Za-z]{4})*$'
    $grouped = New-Object -TypeName System.Collections.Specialized.OrderedDictionary

    foreach ($entry in $catalog.SelectNodes('/ModelList/Model'))
    {
        $rawName = [string]$entry.GetAttribute('name')
        if ([string]::IsNullOrWhiteSpace($rawName))
        {
            Write-Verbose 'Skipping a catalog entry with no name attribute.'
            continue
        }

        $friendlyName = $rawName.Trim()
        $suffixMatch = [regex]::Match($friendlyName, $typeSuffix)
        if ($suffixMatch.Success)
        {
            $friendlyName = $suffixMatch.Groups['Name'].Value.Trim()
        }

        $architecture = [string]$entry.GetAttribute('arch')
        if ([string]::IsNullOrWhiteSpace($architecture))
        {
            $architecture = 'Unspecified'
        }

        if ($PerArchitecture)
        {
            $key = '{0}|{1}' -f $friendlyName, $architecture
        }
        else
        {
            $key = $friendlyName
        }

        if (-not $grouped.Contains($key))
        {
            $grouped[$key] = [PSCustomObject]@{
                Model        = $friendlyName
                Architecture = New-Object -TypeName 'System.Collections.Generic.SortedSet[string]'
                MachineType  = New-Object -TypeName 'System.Collections.Generic.SortedSet[string]'
            }
        }

        $null = $grouped[$key].Architecture.Add($architecture)

        foreach ($typeNode in $entry.SelectNodes('Types/Type'))
        {
            $machineType = ([string]$typeNode.InnerText).Trim().ToUpperInvariant()

            # Machine types are four alphanumeric characters. Anything else would produce a
            # rule that silently matches the wrong hardware.
            if ($machineType -notmatch '^[0-9A-Z]{4}$')
            {
                Write-Warning "Ignoring unexpected machine type '$machineType' on model '$rawName'."
                continue
            }

            $null = $grouped[$key].MachineType.Add($machineType)
        }
    }

    # Carry a brand stripped name so 'T14 Gen 6' matches 'ThinkPad T14 Gen 6'. Only a
    # recognized brand word is removed.
    $brandPrefix = '^(?:ThinkPad|ThinkCentre|ThinkStation)\s+(?<Short>.+)$'

    foreach ($key in $grouped.Keys)
    {
        $group = $grouped[$key]
        if ($group.MachineType.Count -eq 0)
        {
            Write-Verbose "Skipping '$($group.Model)' - the catalog lists no machine types for it."
            continue
        }

        $shortModel = $group.Model
        $brandMatch = [regex]::Match($group.Model, $brandPrefix)
        if ($brandMatch.Success)
        {
            $shortModel = $brandMatch.Groups['Short'].Value.Trim()
        }

        [PSCustomObject]@{
            Model        = $group.Model
            ShortModel   = $shortModel
            Architecture = [string[]]$group.Architecture
            MachineType  = [string[]]$group.MachineType
        }
    }
}

function New-LnvFilterRule
{
    <#
    .SYNOPSIS
        Builds an Intune assignment filter rule matching a set of machine type prefixes.
    .PARAMETER MachineType
        The four character machine types to match.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds and returns a rule string in process. Nothing outside the session is changed.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$MachineType
    )

    # Lenovo reports device.model as the full machine type model, for example 21N1CTO1WW,
    # so the rule matches on the four character prefix rather than an exact value.
    $clauses = foreach ($type in $MachineType)
    {
        '(device.model -startsWith "{0}")' -f $type
    }

    $clauses -join ' or '
}

function Get-IntuneAssignmentFilter
{
    <#
    .SYNOPSIS
        Returns every assignment filter in the tenant, keyed by display name.
    .PARAMETER ApiVersion
        Graph endpoint to call.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiVersion
    )

    $existing = @{}
    $uri = "https://graph.microsoft.com/$ApiVersion/deviceManagement/assignmentFilters"

    while (-not [string]::IsNullOrWhiteSpace($uri))
    {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri

        if ($response.ContainsKey('value'))
        {
            foreach ($filter in $response['value'])
            {
                $displayName = [string]$filter['displayName']
                if (-not $existing.ContainsKey($displayName))
                {
                    $existing[$displayName] = $filter
                }
            }
        }

        if ($response.ContainsKey('@odata.nextLink'))
        {
            $uri = [string]$response['@odata.nextLink']
        }
        else
        {
            $uri = $null
        }
    }

    $existing
}

function New-IntuneAssignmentFilter
{
    <#
    .SYNOPSIS
        Creates an assignment filter in Intune.
    .PARAMETER DisplayName
        Filter display name. Must be unique in the tenant.
    .PARAMETER Description
        Filter description.
    .PARAMETER Rule
        The filter rule.
    .PARAMETER ApiVersion
        Graph endpoint to call.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Rule,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiVersion
    )

    if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Create Intune assignment filter'))
    {
        return
    }

    $body = @{
        displayName                    = $DisplayName
        description                    = $Description
        platform                       = 'windows10AndLater'
        rule                           = $Rule
        assignmentFilterManagementType = 'devices'
        roleScopeTags                  = @('0')
    }

    $uri = "https://graph.microsoft.com/$ApiVersion/deviceManagement/assignmentFilters"
    Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json'
}

function Update-IntuneAssignmentFilter
{
    <#
    .SYNOPSIS
        Updates the rule and description on an existing assignment filter.
    .PARAMETER FilterId
        Identifier of the filter to update.
    .PARAMETER DisplayName
        Display name of the filter, used for the confirmation prompt.
    .PARAMETER Description
        Replacement description.
    .PARAMETER Rule
        Replacement rule.
    .PARAMETER ApiVersion
        Graph endpoint to call.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FilterId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Description,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Rule,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiVersion
    )

    if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Update Intune assignment filter'))
    {
        return
    }

    $body = @{
        description = $Description
        rule        = $Rule
    }

    $uri = "https://graph.microsoft.com/$ApiVersion/deviceManagement/assignmentFilters/$FilterId"
    $null = Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json'
}

# --- main logic ---

$catalogEntries = @(Get-LnvModelCatalog -PerArchitecture:$SplitByArchitecture)
Write-Verbose "Catalog resolved to $($catalogEntries.Count) entries."

if ($PSBoundParameters.ContainsKey('Model'))
{
    # Collapse stray whitespace so 'T14  Gen 6' behaves like 'T14 Gen 6'.
    $pattern = @($Model | ForEach-Object { ($_ -replace '\s+', ' ').Trim() })
    $matchedPattern = New-Object -TypeName 'System.Collections.Generic.HashSet[string]'

    $selected = @(foreach ($entry in $catalogEntries)
        {
            $isMatch = $false
            foreach ($candidate in $pattern)
            {
                # Match the catalog name with or without its brand word. Every pattern is
                # tested rather than stopping at the first hit, so overlapping patterns are
                # all recorded as matched and the entry is still emitted only once.
                if ($entry.Model -like $candidate -or $entry.ShortModel -like $candidate)
                {
                    $null = $matchedPattern.Add($candidate)
                    $isMatch = $true
                }
            }

            if ($isMatch)
            {
                $entry
            }
        })

    foreach ($candidate in $pattern)
    {
        if (-not $matchedPattern.Contains($candidate))
        {
            Write-Warning "No catalog model matched '$candidate'."
        }
    }
}
elseif ($PSBoundParameters.ContainsKey('MachineType'))
{
    # Intune reports the full machine type model, so accept a value pasted straight from
    # the portal ('21N1CTO1WW') as well as the bare machine type ('21N1') and reduce both
    # to the four character prefix the catalog is keyed on.
    $requestedType = New-Object -TypeName 'System.Collections.Generic.HashSet[string]'

    # Every machine type the catalog knows about. Wildcards are expanded against this up
    # front so the rest of the lookup only ever deals with concrete machine types.
    $knownType = New-Object -TypeName 'System.Collections.Generic.HashSet[string]'
    foreach ($entry in $catalogEntries)
    {
        foreach ($candidate in $entry.MachineType)
        {
            $null = $knownType.Add($candidate)
        }
    }

    foreach ($value in $MachineType)
    {
        $trimmed = ($value -replace '\s', '').Trim()

        if ($trimmed -match '[*?]')
        {
            if ($trimmed -notmatch '^[0-9A-Za-z*?]+$')
            {
                Write-Warning "Ignoring '$value' - a machine type pattern may contain only letters, digits, * and ?."
                continue
            }

            $expanded = @(foreach ($candidate in $knownType)
                {
                    if ($candidate -like $trimmed)
                    {
                        $candidate
                    }
                })

            if ($expanded.Count -eq 0)
            {
                Write-Warning "No catalog machine type matched '$trimmed'."
                continue
            }

            foreach ($candidate in $expanded)
            {
                $null = $requestedType.Add($candidate)
            }

            Write-Verbose "'$trimmed' expanded to $(($expanded | Sort-Object) -join ', ')."
            continue
        }

        # No wildcard, so this is either a bare machine type or a full device.model value.
        if ($trimmed -notmatch '^[0-9A-Za-z]{4}')
        {
            Write-Warning "Ignoring '$value' - a machine type starts with four alphanumeric characters, for example 21N1 or 21N1CTO1WW."
            continue
        }

        $null = $requestedType.Add($trimmed.Substring(0, 4).ToUpperInvariant())
    }

    if ($requestedType.Count -eq 0)
    {
        throw "No usable machine type was supplied: $($MachineType -join ', ')."
    }

    $matchedType = New-Object -TypeName 'System.Collections.Generic.HashSet[string]'

    $selected = @(foreach ($entry in $catalogEntries)
        {
            $isMatch = $false
            foreach ($candidate in $entry.MachineType)
            {
                if ($requestedType.Contains($candidate))
                {
                    $null = $matchedType.Add($candidate)
                    $isMatch = $true
                }
            }

            if ($isMatch)
            {
                $entry
            }
        })

    foreach ($candidate in $requestedType)
    {
        if (-not $matchedType.Contains($candidate))
        {
            Write-Warning "No catalog model contains machine type '$candidate'."
        }
    }

    # A machine type belongs to exactly one architecture, so pairing -MachineType with
    # -SplitByArchitecture always narrows to that architecture alone.
    if ($SplitByArchitecture)
    {
        foreach ($entry in $selected)
        {
            $hitType = @(foreach ($candidate in $entry.MachineType)
                {
                    if ($requestedType.Contains($candidate))
                    {
                        $candidate
                    }
                })

            foreach ($other in $catalogEntries)
            {
                if ($other.Model -ne $entry.Model)
                {
                    continue
                }

                # Architecture holds a single value once the catalog is split, but join it
                # anyway - comparing arrays with -eq filters instead of testing equality.
                if (($other.Architecture -join ', ') -eq ($entry.Architecture -join ', '))
                {
                    continue
                }

                $isSelected = $false
                foreach ($candidate in $other.MachineType)
                {
                    if ($requestedType.Contains($candidate))
                    {
                        $isSelected = $true
                        break
                    }
                }

                if ($isSelected)
                {
                    continue
                }

                $note = '{0} resolved to {1} ({2}). The {3} variant ({4}) is a separate filter and was not included.' -f ($hitType -join ', '), $entry.Model, ($entry.Architecture -join ', '), ($other.Architecture -join ', '), ($other.MachineType -join ', ')
                Write-Warning $note
            }
        }
    }
}
else
{
    $selected = $catalogEntries
}

if ($selected.Count -eq 0)
{
    # Name what missed - the per pattern warnings above cover it interactively, but this
    # is the only record left when warnings are suppressed or the streams are split.
    if ($PSBoundParameters.ContainsKey('MachineType'))
    {
        throw "No catalog model contains machine type: $($MachineType -join ', ')"
    }

    throw "No catalog model matched: $($Model -join ', ')"
}

Write-Verbose "Selected $($selected.Count) model(s): $(($selected | Select-Object -ExpandProperty Model -Unique) -join '; ')"

if ($ListAvailable)
{
    $selected | Select-Object -Property Model,
    @{ Name = 'Architecture'; Expression = { $_.Architecture -join ', ' } },
    @{ Name = 'MachineTypeCount'; Expression = { $_.MachineType.Count } },
    @{ Name = 'MachineType'; Expression = { $_.MachineType -join ', ' } }
    return
}

if ($null -eq (Get-MgContext))
{
    Connect-MgGraph -Scopes 'DeviceManagementConfiguration.ReadWrite.All' -NoWelcome
}

Write-Verbose 'Reading existing assignment filters.'
$existingFilter = Get-IntuneAssignmentFilter -ApiVersion $GraphApiVersion
$generated = Get-Date -Format 'yyyy-MM-dd'

foreach ($entry in $selected)
{
    $architectureList = $entry.Architecture -join ', '

    if ($SplitByArchitecture)
    {
        $displayName = '{0}{1} ({2})' -f $NamePrefix, $entry.Model, $architectureList
    }
    else
    {
        $displayName = '{0}{1}' -f $NamePrefix, $entry.Model
    }

    $machineTypeList = $entry.MachineType -join ', '
    $rule = New-LnvFilterRule -MachineType $entry.MachineType
    $description = 'Machine types: {0}. Architecture: {1}. Generated from the Lenovo model catalog on {2}.' -f $machineTypeList, $architectureList, $generated

    if ($rule.Length -gt $script:MaxRuleLength)
    {
        Write-Warning "Skipping '$displayName' - the rule is $($rule.Length) characters and Intune allows $script:MaxRuleLength."
        continue
    }

    if ($existingFilter.ContainsKey($displayName))
    {
        $current = $existingFilter[$displayName]

        if (-not $Force)
        {
            [PSCustomObject]@{
                Model       = $entry.Model
                DisplayName = $displayName
                MachineType = $machineTypeList
                Action      = 'Skipped'
                Detail      = 'A filter with this name already exists. Re-run with -Force to update its rule.'
            }
            continue
        }

        if ([string]$current['rule'] -eq $rule)
        {
            [PSCustomObject]@{
                Model       = $entry.Model
                DisplayName = $displayName
                MachineType = $machineTypeList
                Action      = 'Unchanged'
                Detail      = 'The existing rule already matches the catalog.'
            }
            continue
        }

        try
        {
            Update-IntuneAssignmentFilter -FilterId ([string]$current['id']) -DisplayName $displayName -Description $description -Rule $rule -ApiVersion $GraphApiVersion
            $action = 'Updated'
            $detail = 'Rule replaced from the catalog.'
        }
        catch
        {
            $action = 'Failed'
            $detail = "$_"
            Write-Error "Failed to update '$displayName': $_" -ErrorAction Continue
        }

        [PSCustomObject]@{
            Model       = $entry.Model
            DisplayName = $displayName
            MachineType = $machineTypeList
            Action      = $action
            Detail      = $detail
        }
        continue
    }

    try
    {
        $null = New-IntuneAssignmentFilter -DisplayName $displayName -Description $description -Rule $rule -ApiVersion $GraphApiVersion
        $action = 'Created'
        $detail = '{0} machine type(s) matched.' -f $entry.MachineType.Count
    }
    catch
    {
        $action = 'Failed'
        $detail = "$_"
        Write-Error "Failed to create '$displayName': $_" -ErrorAction Continue
    }

    [PSCustomObject]@{
        Model       = $entry.Model
        DisplayName = $displayName
        MachineType = $machineTypeList
        Action      = $action
        Detail      = $detail
    }
}
