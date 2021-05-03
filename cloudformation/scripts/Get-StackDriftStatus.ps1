#!/usr/bin/env pwsh
#Requires -Modules AWS.Tools.Common, AWS.Tools.CloudFormation
#Requires -Version 7

[CmdletBinding()]
param (
    [Parameter(Mandatory,HelpMessage="The region(s) to collect drift status in")]
    [String[]]
    $Region
    ,
    [Parameter(HelpMessage="Specific Cloudformation stacks to check drift detection on")]
    [String[]]
    $StackName
)

foreach ($currentRegion in $Region) {
  if ($StackName.Count -gt 0) {
    $stacks = Get-CFNStack -Region $currentRegion | Where-Object -Property StackName -In -Value $StackName
  } else {
    $stacks = Get-CFNStack -Region $currentRegion
  }
  $stackDriftStatus = $stacks
  | Select-Object StackName, @{Label="DriftStatus"; Expression={$PSitem.DriftInformation.StackDriftStatus}}

  $stackDriftInfo = $stackDriftStatus
    | Where-Object -Property DriftStatus -EQ -Value Drifted
    | ForEach-Object {
      $details = Get-CFNDetectedStackResourceDrift -Region $currentRegion -StackName $PSItem.StackName
      | Where-Object -Property StackResourceDriftStatus -NE -Value IN_SYNC
      $driftDetails = [PSCustomObject]@{
        ResourceType = $details.ResourceType
        PhysicalId = $details.PhysicalResourceId
        ResourceDriftStatus = $details.StackResourceDriftStatus
        Actual = $details.ActualProperties | ConvertFrom-Json -AsHashtable
        Expected = $details.ExpectedProperties | ConvertFrom-Json -AsHashtable
      }
      $stackDriftDetails = [PSCustomObject]@{
        StackName = $PSItem.StackName
        DriftDetails = $driftDetails
      }
      $stackDriftDetails
    }

  $stackDriftInfo

}

<#
.SYNOPSIS
Get drift detection status on CloudFormation stacks 
.DESCRIPTION
Get drift detection status for all or a selected set of stacks, in one or more regions.
If no stack names are specified, all stacks in a particular region will be used
when checking drift detection status.

Returns information about selected stacks that are in deriftd status and information about the resources
that are not in sync.

.PARAMETER Region
Specify one or more AWS regions to check drift detection in, for this AWS Account.
Separate multiple entries with comma.
This parameter is mandatory

.PARAMETER StackName
If drift detection status check shall be performed on only a selected set of stacks, specify
stack names with this parameter.
Separate multiple entries with comma.
The same names will be applied for all regions specified.

.EXAMPLE
./Get-StackDriftStatus.ps1 -Region eu-west-1

Get drift detection status on all CloudFormation stacks in the account in region eu-west-1.

.EXAMPLE
./Get-StackDriftStatus.ps1 -Region eu-west-1,eu-north-1

Get drift detection status on all CloudFormation stacks in the account in regions eu-west-1 and eu-north-1.

.EXAMPLE
./Get-StackDriftStatus.ps1 -Region eu-west-1,eu-north-1 -StackName vpc-stack,CDKToolkit

Get drift detection status on CloudFormation stacks vpc-stack and CDKToolkiy in the account
in regions eu-west-1 and eu-north-1.
#>
 