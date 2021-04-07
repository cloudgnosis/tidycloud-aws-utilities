#!/usr/bin/env pwsh
#Requires -Modules AWS.Tools.Common, AWS.Tools.Budgets, AWS.Tools.SecurityToken
#Requires -Version 7

[CmdletBinding()]
param (
    [Parameter(Mandatory, HelpMessage="The name of the budget to set")]
    [String]
    $BudgetName
    ,
    # Budget amount in USD
    [Parameter(Mandatory,HelpMessage="The monthly budget limit amount in USD")]
    [Double]
    $Amount
    ,
    # Number of months
    [Parameter(HelpMessage="The number of months the monthly budget is valid for, including the current month")]
    [Int32]
    $NumberOfMonths = 1
    ,
    # Actual percentage threshold
    [Parameter(HelpMessage="Percentage threshold for notification, actual incurred cost relative to monthly budget limit")]
    [Double]
    $ActualPercentageThreshold = 80
    ,
    # Forecasted threshold percentage
    [Parameter(HelpMessage="Percentage threshold for notification forecasted cost relative to monthly budget limit")]
    [Double]
    $ForecastPercentageThreshold = 100
    ,
    # Actual multiplier threshold
    [Parameter(HelpMessage="A multiplier of monthly budget limit, notification when the actual cost reaches multiplied amount")]
    [Double]
    $ActualMultiplierThreshold = 1.5
    ,
    # Notification email
    [Parameter(Mandatory, HelpMessage="Email address to send notifications to")]
    [String]
    $NotificationEmail
    ,
    # Tag key
    [Parameter(HelpMessage="Name of the tag to apply for cost filter")]
    [String]
    $TagKey
    ,
    # Tag value
    [Parameter(HelpMessage="Value of tag to apply for cost filter. Default is an empty value. It is only used if TagKey is specified")]
    [String]
    $TagValue = ""
    ,
    # Cost filter region
    [Parameter(HelpMessage="Region value(s) to apply for cost filter")]
    [String[]]
    $FilterRegion
)

$accountId = (Get-STSCallerIdentity).Account
[array]$budgets = Get-BGTBudgetList -AccountId $accountId | Where-Object -Property BudgetName -eq -Value $BudgetName

$now = Get-Date
$startTime = $now.AddDays(1-$now.Day)
$endTime = $startTime.AddMonths($NumberOfMonths).AddDays(-1)

$actualPercentNotification = @{
    NotificationType = "ACTUAL"
    ComparisonOperator = "GREATER_THAN"
    Threshold = $ActualPercentageThreshold
    ThresholdType = "PERCENTAGE"
}
$forecastPercentNotification = @{
    NotificationType = "FORECASTED"
    ComparisonOperator = "GREATER_THAN"
    Threshold = $ForecastPercentageThreshold
    ThresholdType = "PERCENTAGE"
}
$actualmultiplierNotification = @{
    NotificationType = "ACTUAL"
    ComparisonOperator = "GREATER_THAN"
    Threshold = $ActualMultiplierThreshold * $Amount
    ThresholdType = "ABSOLUTE_VALUE"
}
$notification1 = New-Object Amazon.Budgets.Model.NotificationWithSubscribers
$notification1.Notification = $actualPercentNotification
$notification1.Subscribers.Add(@{
    Address = @($NotificationEmail)
    SubscriptionType = "EMAIL"
})
$notification2 = New-Object Amazon.Budgets.Model.NotificationWithSubscribers
$notification2.Notification = $forecastPercentNotification
$notification2.Subscribers.Add(@{
    Address = @($NotificationEmail)
    SubscriptionType = "EMAIL"
})
$notification3 = New-Object Amazon.Budgets.Model.NotificationWithSubscribers
$notification3.Notification = $actualmultiplierNotification
$notification3.Subscribers.Add(@{
    Address = @($NotificationEmail)
    SubscriptionType = "EMAIL"
})

$costFilter = @{}

if ($PSBoundParameters.ContainsKey("TagKey")) {
    if (-Not $TagKey.StartsWith('aws:')) {
        $Tagkey = "user:$TagKey"
    }
    $costFilter.Add('TagKeyValue', "$TagKey`$$TagValue")
}

if ($PSBoundParameters.ContainsKey("FilterRegion")) {
    $costFilter.Add('Region', $FilterRegion)
}

if ($budgets.Count -eq 0) {
    New-BGTBudget -Budget_BudgetName $BudgetName -AccountId $accountId `
                    -Budget_BudgetType COST -BudgetLimit_Amount $Amount -BudgetLimit_Unit USD `
                    -Budget_TimeUnit MONTHLY -TimePeriod_Start $startTime -TimePeriod_End $endTime `
                    -Budget_CostFilter $costFilter `
                    -NotificationsWithSubscriber @($notification1, $notification2, $notification3)
} else {
    Update-BGTBudget -NewBudget_BudgetName $BudgetName -AccountId $accountId `
                     -NewBudget_BudgetType COST -BudgetLimit_Amount $Amount -BudgetLimit_Unit USD `
                     -NewBudget_TimeUnit MONTHLY -TimePeriod_Start $startTime -TimePeriod_End $endTime `
                     -NewBudget_CostFilter $costFilter

    Get-BGTNotificationsForBudget -BudgetName $BudgetName -AccountId $accountId | ForEach-Object {
        Remove-BGTNotification -BudgetName $BudgetName -AccountId $accountId -Notification_Threshold $_.Threshold `
                               -Notification_ThresholdType $_.ThresholdType -Notification_ComparisonOperator $_.ComparisonOperator `
                               -Notification_NotificationType $_.NotificationType -Force
    }

    $subscriber = New-Object Amazon.Budgets.Model.Subscriber
    $subscriber.Address = @($NotificationEmail)
    $subscriber.SubscriptionType = "EMAIL"
    New-BGTNotification -BudgetName $BudgetName -AccountId $accountId -Notification_ComparisonOperator GREATER_THAN `
                        -Notification_NotificationType ACTUAL -Notification_ThresholdType PERCENTAGE `
                        -Notification_Threshold $ActualPercentageThreshold -Subscriber @($subscriber)

    New-BGTNotification -BudgetName $BudgetName -AccountId $accountId -Notification_ComparisonOperator GREATER_THAN `
                        -Notification_NotificationType FORECASTED -Notification_ThresholdType PERCENTAGE `
                        -Notification_Threshold $ForecastPercentageThreshold -Subscriber @($subscriber)

    New-BGTNotification -BudgetName $BudgetName -AccountId $accountId -Notification_ComparisonOperator GREATER_THAN `
                        -Notification_NotificationType ACTUAL -Notification_ThresholdType ABSOLUTE_VALUE `
                        -Notification_Threshold ($ActualMultiplierThreshold * $Amount) -Subscriber @($subscriber)
}

<#
.SYNOPSIS
Create or update a simple monthly cost budget in an AWS account
.DESCRIPTION
Create or update a simple monthly cost budget, for a limited period. This sets up a monthly cost budget in an AWS account with three types of notifications:

- When actual incurred cost reaches a specified percentage for the monthly budget amount
- When the forecasted cost for a month reaches a specified percentage for the monthly budget amount
- When actual incurred cost reaches a multiplier of the monthly budget amount

The purpose of this script is to create a non-recurring opinionated monthly cost budget without too many options to consider.

.PARAMETER BudgetName
The name that is associated with the budget. This name should be unique within the AWS account it is applied to.
This parameter is mandatory

.PARAMETER Amount
The amount in USD that the budget limit is set to.
This parameter is mandatory.

.PARAMETER NumberOfMonths
The number of months that the budget is valid for. The default is 1.
The budget will always start with the current month when the script is invoked.
Thus with the value 1, the budget is valid for the start to the end of the current month only.

.PARAMETER ActualPercentageThreshold
This is a percentage value of the budget limit, where it will notify in case the actual cost incurred has passed that threshold.
The default is 80 (i.e. 80%).
Thus with the default value, if the monthly budget limit is 100 USD, the notification will trigger when the actual cost in the month is greater than 80 USD.

.PARAMETER ForecastPercentageThreshold
This is a percentage value of the budget limit, where it will notify in case the forecasted cost for the month has passed that threshold.
The default is 100 (i.e. 100%)
Thus with the default value, if the monthly budget limit is 100 USD, the notification will trigger when the forecasted cost for the month is greater than 100 USD.

.PARAMETER ActualMultiplierThreshold
This is a multiplier value applied to the budget limit, where it will notify if the actual cost incurred passes the budget limit multiplied by the multiplier.
The default value is 1.5.
Thus with the default value, if the monthly budget limit is 100 USD, the notification will trigger when the actual cost in the month is greater than 150 USD.

.PARAMETER NotificationEmail
Email address to send notifications to. All notifications are sent to this email address.

.PARAMETER TagKey
Name of the tag to use as a filter for what should be included in the budget. I.e. only resources with the specified tag will be included.
Note: Tag name must have been activated as cost allocation tag through the billing dashboard to work as a filter here.

.PARAMETER TagValue
Value of the tag to use as a filter for what should be included in the budget. I.e. only resources with the TagKey tag and its value set to TagValue will be included.

.PARAMETER FilterRegion
AWS Region identifier(s) for what regions to include in the budget. If not specified, then all regions are included.
Multiple regions can be specified, separated by commas. Region identifiers look like eu-west-1, us-east-1, me-south-1.

.EXAMPLE
./Set-SimpleBudget.ps1 -BudgetName ExampleBudget1 -Amount 100 -NotificationEmail budget-alert@example.com

  Create/update a budget (name ExampleBudget1) with a monthly budget limit of 100 USD for all regions and all resources in the account, valid for the current month. 
  Send email notifications to budget-alert@example.com, with notifications being sent when:
   - Incurred cost is greater than 80 USD
   - Forecasted monthly cost will be greater than 100 USD
   - Incurred cost is greater than 150 USD

.EXAMPLE
./Set-SimpleBudget.ps1 -BudgetName ExampleBudget2 -Amount 50 -NotificationEmail budget-alert@example.com -ActualPercentageThreshold 90 -ForecastedPercentageThreshold 120 -ActualMultiplierThreshold 2

  Create/update a budget (name ExampleBudget2) with a monthly budget limit of 50 USD for all regions and all resources in the account, valid for the current month. 
  Send email notifications to budget-alert@example.com, with notifications being sent when:
   - Incurred cost is greater than 45 USD
   - Forecasted monthly cost will be greater than 120 USD
   - Incurred cost is greater than 100 USD

.EXAMPLE
./Set-SimpleBudget.ps1 -BudgetName ExampleBudget3 -Amount 100 -NotificationEmail budget-alert@example.com -NumberOfMonths 3 -TagKey Project -TagValue SolutionPilot

  Create/update a budget (name ExampleBudget3) with a monthly budget limit of 100 USD for all regions and resources tagged with Project=SolutionPilot.
  The budget is valid for three months, starting with the current month. 
  Send email notifications to budget-alert@example.com, with notifications being sent when:
   - Incurred cost is greater than 80 USD
   - Forecasted monthly cost will be greater than 100 USD
   - Incurred cost is greater than 150 USD

.EXAMPLE
./Set-SimpleBudget.ps1 -BudgetName ExampleBudget4 -Amount 100 -NotificationEmail budget-alert@example.com -FilterRegion eu-west-1,eu-north-1 -TagKey aws:cloudformation:stack-name -TagValue SolutionStack

  Create/update a budget (name ExampleBudget4) with a monthly budget limit of 100 USD for regions eu-west-1 and eu-north-1 and resources included in CloudFormation stack SolutionStack.
  The budget is valid for three months, starting with the current month. 
  Send email notifications to budget-alert@example.com, with notifications being sent when:
   - Incurred cost is greater than 80 USD
   - Forecasted monthly cost will be greater than 100 USD
   - Incurred cost is greater than 150 USD
 #>