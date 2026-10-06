# Assignment Filters

## New-LnvAssignmentFilter.ps1

Creates Intune assignment filters for Lenovo models from the [Lenovo model catalog](https://download.lenovo.com/cdrt/td/catalogv2.xml).

Intune reports `device.model` for Lenovo hardware as the machine type model (`21N1CTO1WW`) rather than the friendly name (`ThinkPad T14s Gen 6`), so a model based filter has to be written against machine type prefixes. This script resolves those prefixes from the catalog and builds the filter rule for you.

A friendly name is spread across several catalog entries carrying a `Type XXXX YYYY` suffix. ThinkPad T14s Gen 6 is five entries covering ten machine types. The suffix is stripped and the machine types are merged, so one filter covers the whole model:

```
(device.model -startsWith "21M1") or (device.model -startsWith "21M2") or ... or (device.model -startsWith "21TC")
```

The catalog collapses to roughly 400 models. The largest rule produced is about 640 characters, well inside Intune's 3072 character limit.

### Requirements

- [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)
- `Microsoft.Graph.Authentication` module
- `DeviceManagementConfiguration.ReadWrite.All` scope

### Usage

List the model names and their machine types. Nothing is created and Graph is not contacted:

```powershell
.\New-LnvAssignmentFilter.ps1 -ListAvailable
.\New-LnvAssignmentFilter.ps1 -Model 'ThinkPad T14*' -ListAvailable
```

Preview what would be created:

```powershell
.\New-LnvAssignmentFilter.ps1 -Model 'ThinkPad T14S Gen 6' -WhatIf
```

Create filters. Wildcards are supported and multiple patterns can be passed:

```powershell
.\New-LnvAssignmentFilter.ps1 -Model 'ThinkPad X1 Carbon*', 'ThinkPad T14*'
```

### Matching

The brand word is optional and matching is case insensitive, so all of these resolve to the same model:

```powershell
.\New-LnvAssignmentFilter.ps1 -Model 'ThinkPad T14 Gen 6'
.\New-LnvAssignmentFilter.ps1 -Model 'T14 Gen 6'
.\New-LnvAssignmentFilter.ps1 -Model 't14 gen 6'
```

Matching stays exact on the rest of the name, so `T14 Gen 6` resolves to `ThinkPad T14 Gen 6` alone and does not pull in `T14S Gen 6`, `P14s`, or `L14`. The filter is always named from the full catalog name no matter how it was matched, so the example above still produces `Lenovo - ThinkPad T14 Gen 6`.

Each pattern is evaluated separately. One that matches nothing raises a warning and the rest of the run continues; the script only stops when no pattern matched anything.

Catalog naming is not consistent across lines. ThinkPad T14 uses `Gen 6`, while most X1 Carbon entries use `12TH Gen` and one uses `Gen 14`. Confirm the name with `-ListAvailable` before a large run:

```powershell
.\New-LnvAssignmentFilter.ps1 -Model '*carbon*' -ListAvailable
```

### Looking up by machine type

When the machine type is known but the marketing name is not, `-MachineType` runs the lookup in reverse. It accepts the bare machine type or the full `device.model` string pasted straight out of the Intune portal:

```powershell
.\New-LnvAssignmentFilter.ps1 -MachineType '21N1' -ListAvailable
.\New-LnvAssignmentFilter.ps1 -MachineType '21N1CTO1WW'
```

Both resolve to `ThinkPad T14S Gen 6`. Only the first four characters are significant.

A machine type selects the whole model it belongs to, so the filter that gets created covers every sibling machine type rather than only the one supplied - looking up `21N1` produces the complete T14s Gen 6 filter across all ten of its machine types. Combine it with `-SplitByArchitecture` to narrow to just the architecture that machine type belongs to:

```powershell
# 21N1 is the Snapdragon variant, so this yields the Qualcomm filter alone
.\New-LnvAssignmentFilter.ps1 -MachineType '21N1' -SplitByArchitecture
```

`-MachineType` and `-Model` cannot be combined.

Split a model into one filter per processor architecture. Several models ship on more than one - T14s Gen 6 spans Intel, AMD and Qualcomm - which matters when driver or firmware targeting has to keep them apart:

```powershell
.\New-LnvAssignmentFilter.ps1 -Model 'ThinkPad T14S Gen 6' -SplitByArchitecture
```

Refresh rules on filters that already exist, picking up machine types Lenovo has added to the catalog since they were created:

```powershell
.\New-LnvAssignmentFilter.ps1 -Model 'ThinkPad*' -Force
```

### Parameters

| Parameter | Description |
|---|---|
| `-Model` | Friendly model names to create filters for. Wildcards supported, brand word optional, case insensitive. Omitting it selects the entire catalog. |
| `-MachineType` | Look the model up by machine type instead. Accepts `21N1` or `21N1CTO1WW`. Cannot be combined with `-Model`. |
| `-ListAvailable` | Outputs model names and machine types without contacting Graph. |
| `-SplitByArchitecture` | One filter per architecture instead of one per model. |
| `-NamePrefix` | Prepended to every filter display name. Defaults to `Lenovo - `. |
| `-GraphApiVersion` | `beta` (default) or `v1.0`. |
| `-Force` | Updates the rule on a filter that already exists with the same name. |

### Output

One object per model with an `Action` of `Created`, `Updated`, `Unchanged`, `Skipped`, or `Failed`, so a run can be piped to `Export-Csv` for a record of what changed.

### Notes

- Filters are created for the `windows10AndLater` platform with an `assignmentFilterManagementType` of `devices`.
- Display names come from the catalog verbatim, which uses `T14S` where marketing uses `T14s`. Adjust `-NamePrefix` or rename in the portal if house style differs.
- Existing filters are matched by display name and left alone unless `-Force` is passed.
