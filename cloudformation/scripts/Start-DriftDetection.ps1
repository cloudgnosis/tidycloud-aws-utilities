#!/usr/bin/env pwsh
#Requires -Modules AWS.Tools.Common, AWS.Tools.CloudFormation
#Requires -Version 7
[CmdletBinding()]
param (
    [Parameter(Mandatory,HelpMessage="The region(s) to perform drift detection in")]
    [String[]]
    $Region
    ,
    [Parameter(HelpMessage="Specific Cloudformation stacks to perform drift detection on")]
    [String[]]
    $StackName
)

$validStackStatus = "CREATE_COMPLETE","UPDATE_COMPLETE","UPDATE_ROLLBACK_COMPLETE","UPDATE_ROLLBACK_FAILED"
$result = @()

foreach ($currentRegion in $Region) {
  if ($StackName.Count -gt 0) {
    $stacks = Get-CFNStack -Region $currentRegion | Where-Object -Property StackName -In -Value $StackName
  } else {
    $stacks = Get-CFNStack -Region $currentRegion
  }

  foreach ($stack in $stacks) {
    if ($stack.StackStatus -in $validStackStatus) {
      Start-CFNStackDriftDetection -Region $currentRegion -StackName $stack.StackName >$null
      $result += [PSCustomObject]@{ StackName=$stack.StackName; Region = $currentRegion }
    }
  }
}
$result

<#
.SYNOPSIS
Start drift detection on CloudFormation stacks 
.DESCRIPTION
Start drift detection for all or a selected set of stacks, in one or more regions.
If no stack names are specified, all stacks in a particular region will be used
when initiating drift detection.

Drift detection are only applied to stacks in one of these states:
- CREATE_COMPLETE
- UPDATE_COMPLETE
- UPDATE_ROLLBACK_COMPLETE
- UPDATE_ROLLBACK_FAILED

Other states you will not be able to perform drift detection, so this
script will skip these.
Returns stack name and region for the stacks where the script started drift detection.

.PARAMETER Region
Specify one or more AWS regions to perform drift detection in, for this AWS Account.
Separate multiple entries with comma.
This parameter is mandatory

.PARAMETER StackName
If drift detection shall be performed on only a selected set of stacks, specify
stack names with this parameter.
Separate multiple entries with comma.
The same names will be applied for all regions specified.

.EXAMPLE
./Start-DriftDetection.ps1 -Region eu-west-1

Starts drift detection on all CloudFormation stacks in the account in region eu-west-1.

.EXAMPLE
./Start-DriftDetection.ps1 -Region eu-west-1,eu-north-1

Starts drift detection on all CloudFormation stacks in the account in regions eu-west-1 and eu-north-1.

.EXAMPLE
./Start-DriftDetection.ps1 -Region eu-west-1,eu-north-1 -StackName vpc-stack,CDKToolkit

Starts drift detection on CloudFormation stacks vpc-stack and CDKToolkiy in the account
in regions eu-west-1 and eu-north-1.
#>