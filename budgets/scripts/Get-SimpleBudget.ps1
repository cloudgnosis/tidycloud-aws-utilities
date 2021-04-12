#!/usr/bin/env pwsh
#Requires -Modules AWS.Tools.Common, AWS.Tools.Budgets,  AWS.Tools.SecurityToken
#Requires -Version 7

[CmdletBinding()]
param (
    [Parameter(Mandatory, HelpMessage="The name of the budget to get")]
    [String]
    $BudgetName
    ,
    # If a notificastion summary is added or not
    [Parameter(HelpMessage="If set, adds the notification descriptions as a single notification summary text field")]
    [Switch]
    $AddNotificationSummary
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
[string[]]$notificationSummaryArray = @()
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
        SubscriberAddress = $ad 
        Description = "$desc $subscribertext"
    }
    $notificationSummaryArray += "$desc $subscribertext"
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
if ($AddNotificationSummary) {
    Add-Member -InputObject $result -MemberType NoteProperty -Name NotificationSummary -Value ($notificationSummaryArray -join ", ")
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

.PARAMETER AddNotificationSummmary
If specified, adds a field NotificationSummary to the result which contains the notification description
texts of all notification as a single comma-separated text string.

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
Notifications     : {@{Operator=GREATER_THAN; CostType=ACTUAL; Threshold=80; ThresholdType=PERCENTAGE; 
                    SubscriberAddress=alert@example.com; Description=Actual incurred cost > 80 % of 
                    monthly budget limit (EMAIL: alert@example.com)}, @{Operator=GREATER_THAN; 
                    CostType=FORECASTED; Threshold=100; ThresholdType=PERCENTAGE; 
                    SubscriberAddress=alert@example.com; Description=Forecasted cost for the month > 100 
                    % of monthly budget limit (EMAIL: alert@example.com)}}
.EXAMPLE
./Get-SimpleBudget.ps1 -BudgetName TheTestBudget -AddNotificationSummary

BudgetName          : TheTestBudget
StartDate           : 04/01/2021 17:34:22
EndDate             : 04/30/2021 17:34:22
BudgetKind          : Monthly cost
BudgetLimitAmount   : 123.0
BudgetLimitUnit     : USD
LastUpdatedTime     : 04/05/2021 17:34:23
FilterRegions       : 
FilterTags          : 
Notifications       : {@{Operator=GREATER_THAN; CostType=ACTUAL; Threshold=80; ThresholdType=PERCENTAGE; 
                      SubscriberAddress=alert@example.com; Description=Actual incurred cost > 80 % of 
                      monthly budget limit (EMAIL: alert@example.com)}, @{Operator=GREATER_THAN; 
                      CostType=FORECASTED; Threshold=100; ThresholdType=PERCENTAGE; 
                      SubscriberAddress=alert@example.com; Description=Forecasted cost for the month > 
                      100 % of monthly budget limit (EMAIL: alert@example.com)}}
NotificationSummary : Actual incurred cost > 80 % of monthly budget limit (EMAIL: alert@example.com), 
                      Forecasted cost for the month > 100 % of monthly budget limit (EMAIL: 
                      alert@example.com)


#>