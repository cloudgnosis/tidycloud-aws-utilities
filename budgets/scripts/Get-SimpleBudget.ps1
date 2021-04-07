#!/usr/bin/env pwsh
#Requires -Modules AWS.Tools.Common, AWS.Tools.Budgets,  AWS.Tools.SecurityToken
#Requires -Version 7

[CmdletBinding()]
param (
    [Parameter(Mandatory, HelpMessage="The name of the budget to get")]
    [String]
    $BudgetName
)

function Get-NotificationDescription {
    param($NotificationType, $ComparisonOperator, $ThresholdType, $Threshold)

    $op = switch ($ComparisonOperator)  {
        'EQUAL_TO'     { '=' }
        'GREATER_THAN' { '>' }
        'LESS_THAN'    { '<' }
    }
    $cost = $ThresholdType -eq 'ABSOLUTE_VALUE' ? "$Threshold USD" : "$Threshold % of monthly budget limit"
    $costType = $NotificationType -eq 'ACTUAL' ? "Actual incurred cost" : "Forecasted cost for the month"
    "$costType $op $cost"
}


$accountId = (Get-STSCallerIdentity).Account
$budget = Get-BGTBudget -BudgetName $BudgetName -AccountId $accountId
if ($null -eq $budget) {
    write-warning "Oh no, could not find budget with name $BudgetName ! Please check that the name is correct."
    return
}
$timePeriod = $budget.TimePeriod
$budgetlimit = [Amazon.Budgets.Model.Spend]$budget.BudgetLimit
$costFilters = $budget.CostFilters
$regions = $costFilters['Region']
$tags = $costFilters['TagKeyValue']
if ($null -ne $tags) {
    $tags = $tags | ForEach-Object { 
        $k, $v = $PSItem.Split("`$")
        if ($k.StartsWith('user:')) {
            $k = $k.Substring(5)
        }
        "$k = $v"
    }    
}
$notifications = Get-BGTNotificationsForBudget -BudgetName $BudgetName -AccountId $accountId | ForEach-Object {
    $nt = $PSItem.NotificationType
    $co = $PSItem.ComparisonOperator
    $tt = $PSItem.ThresholdType
    $t = $PSItem.Threshold
    $desc = Get-NotificationDescription -NotificationType $nt -ComparisonOperator $co -ThresholdType $tt -Threshold $t
    $subscriber = Get-BGTSubscribersForNotification -BudgetName $BudgetName -AccountId $accountId -Notification_ComparisonOperator $co `
                                                     -Notification_NotificationType $nt -Notification_ThresholdType $tt `
                                                     -Notification_Threshold $t
    $st = $subscriber.SubscriptionType
    $ad = $subscriber.Address
    $subscribertext = "($st`: $ad)"

    $notification = [PSCustomObject]@{
        Operator = $co
        CostType = $nt
        Threshold = $t
        ThresholdType = $tt -eq 'ABSOLUTE_VALUE' ? $tt : 'PERCENTAGE'
        SubscriberAddreess = $ad 
        Description = "$desc $subscribertext"
    }
    $notification
}
$result = [PSCustomObject]@{
    BudgetName = $budget.BudgetName
    StartDate = $timePeriod.Start
    EndDate = $timePeriod.End
    BudgetKind = 'Monthly cost'
    BudgetLimitAmount = $budgetlimit.Amount
    BudgetLimitUnit = $budgetlimit.Unit
    LastUpdatedTime = $budget.LastUpdatedTime
    FilterRegions = $regions
    FilterTags = $tags
    Notifications = $notifications
}

$result

<#
.SYNOPSIS
Get a simple monthly cost budget in an AWS account, created with Set-SimpleBudget.ps1 script.
.DESCRIPTION
Get a simple monthly cost budget.
This only supports the budget features that are set by the corresponding Set-SimpleBudget.ps1 script. 
Additional budget features may not display properly.

.PARAMETER BudgetName
The name that is associated with the budget in the AWS Account.
This parameter is mandatory

.EXAMPLE
./Get-SimpleBudget.ps1 -BudgetName TheTestBudget 

BudgetName        : TheTestBudget
StartDate         : 04/01/2021 17:34:22
EndDate           : 04/30/2021 17:34:22
BudgetKind        : Monthly cost
BudgetLimitAmount : 123.0
BudgetLimitUnit   : USD
LastUpdatedTime   : 04/05/2021 17:34:23
FilterRegions     : 
FilterTags        : 
Notifications     : {@{Operator=GREATER_THAN; CostType=ACTUAL; Threshold=184.5; ThresholdType=ABSOL
                    UTE_VALUE; SubscriberAddreess=alert@example.com; Description=Actual incurred co
                    st > 184.5 USD (EMAIL: alert@example.com)}, @{Operator=GREATER_THAN; CostType=A
                    CTUAL; Threshold=80; ThresholdType=PERCENTAGE; SubscriberAddreess=alert@example
                    .com; Description=Actual incurred cost > 80 % of monthly budget limit (EMAIL: a
                    lert@example.com)}, @{Operator=GREATER_THAN; CostType=FORECASTED; Threshold=100
                    ; ThresholdType=PERCENTAGE; SubscriberAddreess=alert@example.com; Description=F
                    orecasted cost for the month > 100 % of monthly budget limit (EMAIL: alert@exam
                    ple.com)}}

.EXAMPLE
./Get-SimpleBudget.ps1 -BudgetName BTestBudget   

BudgetName        : BTestBudget
StartDate         : 04/01/2021 11:39:49
EndDate           : 04/30/2021 11:39:49
BudgetKind        : Monthly cost
BudgetLimitAmount : 2.5
BudgetLimitUnit   : USD
LastUpdatedTime   : 04/05/2021 11:39:51
FilterRegions     : {eu-west-1, eu-north-1}
FilterTags        : Project = SolutionPilot
Notifications     : {@{Operator=GREATER_THAN; CostType=ACTUAL; Threshold=3.75; ThresholdType=ABSOLU
                    TE_VALUE; SubscriberAddreess=alert@example.com; Description=Actual incurred cost > 
                    3.75 USD (EMAIL: alert@example.com)}, @{Operator=GREATER_THAN; CostType=ACTUAL; Thr
                    eshold=80; ThresholdType=PERCENTAGE; SubscriberAddreess=alert@example.com; Descript
                    ion=Actual incurred cost > 80 % of monthly budget limit (EMAIL: alert@example.com)}
                    , @{Operator=GREATER_THAN; CostType=FORECASTED; Threshold=100; ThresholdType=PE
                    RCENTAGE; SubscriberAddreess=alert@example.com; Description=Forecasted cost for the
                     month > 100 % of monthly budget limit (EMAIL: alert@example.com)}}


#>