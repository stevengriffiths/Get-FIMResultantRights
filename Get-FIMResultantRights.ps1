<#
.NAME
   Get-FIMResultantRights

.SYNOPSIS
   Dump FIM MPRs and permissions

.DESCRIPTION
    Displays the MPRs that contribute permissions for a given
    requestor and target object in the FIM Service database

.NOTES
    File Name   : Get-FIMResultantRights.ps1
    Author      : SCGriffiths (Oxford Computer Group)
    Requires    : PowerShell v2

    TODO:

    - Error handling in SQL
    - Allow Requestor and Target to be something other than GUIDs
    - Allow selection of attribute used to identify Requestor and Target - currently uses DisplayName, but
      could use AccountName or even leave as ObjectID GUID

.EXAMPLE
    Get-FIMResultantRights -Requestor <Guid> -Target <Guid>

.PARAMETER Requestor
    Identifies the Requestor whose permissions will be displayed

.PARAMETER Target
    Identifies the target object that the Requestor is accessing

.PARAMETER Server
    Identifies the server hosting the FIM Service database

.PARAMETER Database
    Identifies the name of the FIM Service database

.PARAMETER Summary
    Display summary level details

.PARAMETER Full
    Displays full details

#>

[CmdletBinding()]
PARAM
(
    [parameter(Mandatory=$false)] [string] $Requestor =  'fb89aefa-5ea1-47f1-8890-abe7797d6497',  # Well-known GUID of installation account...except it was deleted in Dev, so use Built-in sync account!
    [parameter(Mandatory=$false)] [string] $Target = 'fb89aefa-5ea1-47f1-8890-abe7797d6497',      # Well-known GUID of Built-in Sync account
                                  [string] $Server = 'ID2-SQL\FIMSRV',
                                  [string] $Database = 'FIMService',
                                  [switch] $Summary = $false,
                                  [switch] $Full = $false
)


function Write-Header($Requestor, $Target)
{

    $rlen = $Requestor.Length
    $tlen = $Target.Length

    if ($rlen -ge $tlen) {'-' * ($rlen + 11)}
    else {'-' * ($tlen + 11)}

    "Requestor: {0}" -f $Requestor
    "   Target: {0}" -f $Target

    if ($rlen -ge $tlen) {'-' * ($rlen + 11)}
    else {'-' * ($tlen + 11)}

}

function Invoke-Sql
{
    [CmdletBinding()]
    PARAM
    (
        [string] $Server,
        [string] $Database,
        [string] $Sql
    )
    
    $connectionString = "Server={0};Database={1};Integrated Security=True" -f $Server, $Database

    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $command = New-Object System.Data.SqlClient.SqlCommand($Sql, $connection)
    $connection.Open()

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
    $dataset = New-Object System.Data.DataSet
    $adapter.Fill($dataSet) | Out-Null

    $connection.Close()
    $dataSet.Tables
}


$Sql = @"
SET NOCOUNT ON;


DECLARE @PrincipalKey BIGINT = (SELECT [fim].[ObjectKeyFromObjectIdentifier] (N'$Requestor'))
DECLARE @TargetKey    BIGINT = (SELECT [fim].[ObjectKeyFromObjectIdentifier] (N'$Target'))

DECLARE 
		@ComputedMemberAttributeKey            SMALLINT,
		@DisplayNameAttributeKey               SMALLINT,
		@ManagementPolicyRuleTypeRequestString NVARCHAR(16),
		@OperationAdd                          NVARCHAR(16),
		@OperationCreate                       NVARCHAR(16),
		@OperationDelete                       NVARCHAR(16),
		@OperationModify                       NVARCHAR(16),
		@OperationRead                         NVARCHAR(16),
		@OperationRemove                       NVARCHAR(16),
		@PrincipalName                         NVARCHAR(256),
        @SetObjectTypeKey                      SMALLINT,
		@TargetName                            NVARCHAR(256),
		@TrueFlag                              BIT;

SELECT
		@ComputedMemberAttributeKey            = [fim].[AttributeKeyFromName] (N'ComputedMember'),
		@DisplayNameAttributeKey               = [fim].[AttributeKeyFromName] (N'DisplayName'),
		@ManagementPolicyRuleTypeRequestString = N'Request',
		@OperationAdd                          = N'Add',
		@OperationCreate                       = N'Create',
		@OperationDelete                       = N'Delete',
		@OperationModify                       = N'Modify',
		@OperationRead                         = N'Read',
		@OperationRemove                       = N'Remove',
		@SetObjectTypeKey                      = [fim].[ObjectTypeKeyFromName] (N'Set'),
		@TrueFlag                              = CONVERT(BIT,1);


--
-- Get name of requestor principal
--
SET @PrincipalName =
(
SELECT [ovs].[ValueString]
  FROM [fim].[Objects] AS [obj] 
 INNER JOIN [fim].[ObjectValueString] AS [ovs]
    ON [ovs].[ObjectKey] = [obj].[ObjectKey]
 WHERE [ovs].[AttributeKey] = @DisplayNameAttributeKey AND [obj].[ObjectKey] = @PrincipalKey
)

--
-- Get name of target object
--
SET @TargetName =
(
SELECT [ovs].[ValueString]
  FROM [fim].[Objects] AS [obj] 
 INNER JOIN [fim].[ObjectValueString] AS [ovs]
    ON [ovs].[ObjectKey] = [obj].[ObjectKey]
 WHERE [ovs].[AttributeKey] = @DisplayNameAttributeKey AND [obj].[ObjectKey] = @TargetKey
)

--
-- Create a temporary table containing the sets of which the requestor is a member
--
DECLARE @PrincipalSets TABLE
(
	[ObjectKey] BIGINT,
	[Name] NVARCHAR(256)
		PRIMARY KEY
        (
            [ObjectKey]
        )
);

IF EXISTS
(
    SELECT TOP 1 [ovr].[ObjectKey]
      FROM [fim].[ObjectValueReference] AS [ovr]
     WHERE [ovr].[ObjectTypeKey] = @SetObjectTypeKey
       AND [ovr].[ValueReference] = @PrincipalKey
       AND [ovr].[AttributeKey] = @ComputedMemberAttributeKey
)
BEGIN
	INSERT INTO @PrincipalSets
	(
		[ObjectKey],
		[Name]
	)
	SELECT [obj].[ObjectKey], [ovs].[ValueString]
	  FROM [fim].[ObjectValueReference] AS [ovr]
	  LEFT JOIN [fim].[Objects] AS [obj]
		ON [ovr].[ObjectKey] = [obj].[ObjectKey]
     INNER JOIN [fim].[ObjectValueString] AS [ovs]
	    ON [ovs].[ObjectKey] = [obj].[ObjectKey]
	   AND [ovs].[AttributeKey] = @DisplayNameAttributeKey
	 WHERE [ovr].[ObjectTypeKey] = @SetObjectTypeKey
	   AND [ovr].[ValueReference] = @PrincipalKey
	   AND [ovr].[AttributeKey] = @ComputedMemberAttributeKey

	-- DEBUG: Dump principal set names
	--SELECT * FROM @PrincipalSets ORDER BY Name
	--RETURN
END
ELSE
BEGIN
	RAISERROR(N'No sets found for requestor', 16, 1)
	RETURN
END

--
-- Create a temporary table containing the sets of which the target resource is a member
--
DECLARE @ResourceSets TABLE
(
	[ObjectKey] BIGINT,
	[Name] NVARCHAR(256)
		PRIMARY KEY
        (
            [ObjectKey]
        )
);

IF EXISTS
(

    SELECT TOP 1 [ovr].[ObjectKey]
      FROM [fim].[ObjectValueReference] AS [ovr]
     WHERE [ovr].[ObjectTypeKey] = @SetObjectTypeKey
       AND [ovr].[ValueReference] = @TargetKey
       AND [ovr].[AttributeKey] = @ComputedMemberAttributeKey
)
BEGIN
	INSERT INTO @ResourceSets
	(
		[ObjectKey],
		[Name]
	)

	SELECT [obj].[ObjectKey], [ovs].[ValueString]
	  FROM [fim].[ObjectValueReference] AS [ovr]
	  LEFT JOIN [fim].[Objects] AS [obj]
		ON [ovr].[ObjectKey] = [obj].[ObjectKey]
     INNER JOIN [fim].[ObjectValueString] AS [ovs]
	    ON [ovs].[ObjectKey] = [obj].[ObjectKey]
	   AND [ovs].[AttributeKey] = @DisplayNameAttributeKey
	 WHERE [ovr].[ObjectTypeKey] = @SetObjectTypeKey
	   AND [ovr].[ValueReference] = @TargetKey
	   AND [ovr].[AttributeKey] = @ComputedMemberAttributeKey

	-- DEBUG: Dump resource set names
	--SELECT * FROM @ResourceSets ORDER BY Name
	--RETURN
END
ELSE
BEGIN
	RAISERROR(N'No sets found for target', 16, 1)
	RETURN
END


--
-- Get the MPRs where the requestor principal is in PrincipalSet or is PrincipalRelativeToResource
--
SELECT 

	@PrincipalName AS Requestor,
	@TargetName AS [Target],
	[rights].[ValueString] AS MPRName,
	[rights].[ActionType] AS Permission,
	COALESCE([ai].[Name], 'All Attributes') AS Attribute

  FROM 
  (

    -- Get the PrincipalSet MPRs for ActionType Add, Delete, Modify, Read and Remove where the target resource is in ResourceCurrentSet

	-- Start with all MPRs
	SELECT [rule].[ObjectKey], [rule].[ActionParameterAll], [ruleOperation].[ActionType], [ruleAttribute].[ActionParameterKey], [ovs].[ValueString]
	  FROM [fim].[ManagementPolicyRule] AS [rule]

	    -- Remove any MPRs that don't reference sets the Requestor is a member of
	 INNER JOIN @PrincipalSets AS [set]
		ON [set].[ObjectKey] = [rule].[PrincipalSet]

		-- Remove any MPRs that don't reference sets the target is a member of
	  INNER JOIN @ResourceSets AS [res]
		ON [res].[ObjectKey] = [rule].[ResourceCurrentSet]

		-- Get all ActionTypes except Create for the MPRs
	 INNER JOIN [fim].[ManagementPolicyRuleOperation] AS [ruleOperation]
		ON [rule].[ObjectKey] = [ruleOperation].[ObjectKey]
	   AND [ruleOperation].[ActionType] IN (@OperationAdd, @OperationDelete, @OperationModify, @OperationRead, @OperationRemove)

		-- Get all attributes referenced by the MPRs
	  LEFT JOIN [fim].[ManagementPolicyRuleAttribute] AS [ruleAttribute]
		ON [rule].[ObjectKey] = [ruleAttribute].[ObjectKey]

		-- Get the name of the MPR
	  INNER JOIN [fim].[Objects] AS [obj] ON [rule].[ObjectKey] = [obj].[ObjectKey]
	  INNER JOIN [fim].[ObjectValueString] AS [ovs] ON [obj].[ObjectKey] = [ovs].[ObjectKey]

	 WHERE [rule].[ManagementPolicyRuleType] = @managementPolicyRuleTypeRequestString
	   AND [rule].[GrantRight] = @TrueFlag
	   AND [ovs].[AttributeKey] = @DisplayNameAttributeKey

	 UNION

    -- Get the PrincipalSet MPRs for ActionType Create where the target resource is in ResourceFinalSet

	-- Start with all MPRs
	SELECT [rule].[ObjectKey], [rule].[ActionParameterAll], [ruleOperation].[ActionType], [ruleAttribute].[ActionParameterKey], [ovs].[ValueString]
	  FROM [fim].[ManagementPolicyRule] AS [rule]

	    -- Remove any MPRs that don't reference sets the Requestor is a member of
	 INNER JOIN @PrincipalSets AS [set]
		ON [set].[ObjectKey] = [rule].[PrincipalSet]

		-- Remove any MPRs that don't reference sets the target is a member of
	  INNER JOIN @ResourceSets AS [res]
		ON [res].[ObjectKey] = [rule].[ResourceFinalSet]

		-- Get ActionType Create for the MPRs
	 INNER JOIN [fim].[ManagementPolicyRuleOperation] AS [ruleOperation]
		ON [rule].[ObjectKey] = [ruleOperation].[ObjectKey]
	   AND [ruleOperation].[ActionType] = @OperationCreate

		-- Get all attributes referenced by the MPRs
	  LEFT JOIN [fim].[ManagementPolicyRuleAttribute] AS [ruleAttribute]
		ON [rule].[ObjectKey] = [ruleAttribute].[ObjectKey]

		-- Get the name of the MPR
	  INNER JOIN [fim].[Objects] AS [obj] ON [rule].[ObjectKey] = [obj].[ObjectKey]
	  INNER JOIN [fim].[ObjectValueString] AS [ovs] ON [obj].[ObjectKey] = [ovs].[ObjectKey]

	 WHERE [rule].[ManagementPolicyRuleType] = @managementPolicyRuleTypeRequestString
	   AND [rule].[GrantRight] = @TrueFlag
	   AND [ovs].[AttributeKey] = @DisplayNameAttributeKey

	 UNION

	-- Get the PrincipalRelativeToResource MPRs

		 -- Start with all MPRs
	 SELECT [rule].[ObjectKey], [rule].[ActionParameterAll], [ruleOperation].[ActionType], [ruleAttribute].[ActionParameterKey], [ovs].[ValueString]
	   FROM [fim].[ManagementPolicyRule] AS [rule]

	     -- Include MPRs that:
		 -- 1. Refer to the target
		 -- 2. Have the Requestor as PrincipaRelativeToResource
	  INNER JOIN [fim].[ObjectValueReference] AS [ovr]
		 ON 
		  (
				[ovr].[ObjectKey] = @TargetKey                                        -- 1
			AND [ovr].[AttributeKey] = [rule].[PrincipalRelativeToResourceCurrent]    -- 2
			AND [ovr].[ValueReference] = @PrincipalKey                                -- 2
		  )

         -- Get all ActionTypes for the MPRs
	   LEFT JOIN [fim].[ManagementPolicyRuleOperation] AS [ruleOperation]
		 ON [rule].[ObjectKey] = [ruleOperation].[ObjectKey]

		 -- Get all attributes referenced by the MPRs
	   LEFT JOIN [fim].[ManagementPolicyRuleAttribute] AS [ruleAttribute]
		 ON [rule].[ObjectKey] = [ruleAttribute].[ObjectKey]

	     -- Get the name of the MPR
	  INNER JOIN [fim].[Objects] AS [obj] ON [rule].[ObjectKey] = [obj].[ObjectKey]
	  INNER JOIN [fim].[ObjectValueString] AS [ovs] ON [obj].[ObjectKey] = [ovs].[ObjectKey]

	    -- Get request MPRs that grant permissions
	 WHERE [rule].[ManagementPolicyRuleType] = @managementPolicyRuleTypeRequestString
	   AND [rule].[GrantRight] = @TrueFlag
	   AND [rule].[ResourceCurrentSet]

	    -- And reference the target in ResourceCurrentSet
		IN
		 (
				SELECT [ovr].[ObjectKey]
				  FROM [fim].[ObjectValueReference] AS [ovr]
				 WHERE
					 (
							[ovr].ObjectTypeKey = @SetObjectTypeKey
						AND [ovr].AttributeKey = @ComputedMemberAttributeKey
						AND [ovr].ValueReference = @TargetKey
					 )
		 )
	   AND [ovs].[AttributeKey] = @DisplayNameAttributeKey

  ) AS [rights]

 -- Get the attribute name
 LEFT JOIN [fim].[AttributeInternal] AS [ai] ON [rights].[ActionParameterKey] = [ai].[Key]

 ORDER BY MPRName, Permission, Attribute

"@


#
# Convert the data table to a PSObject
#
$properties = @{Requestor=''; Target=''; MPR=''; Permission=''; Attribute=''}
$objectTemplate = New-Object -TypeName PSObject -Property $properties

$rightsCollection = @((Invoke-Sql $Server $Database $Sql) |

    ForEach-Object {

        $thisRight = $_
        $thisObject = $objectTemplate.PSObject.Copy()
        $thisObject.Requestor = $thisRight.Requestor
        $thisObject.Target = $thisRight.Target
        $thisObject.MPR = $thisRight.MPRName
        $thisObject.Permission = $thisRight.Permission
        $thisObject.Attribute = $thisRight.Attribute
        $thisObject

    })

#
# Report the permissions
#

# Provide a summary showing requestor, target, MPRs and permissions

if ($Summary -eq $true)
{

    if ($rightsCollection.Count -eq 0)
    {

        Write-Host "The requestor has no permissions on the target object"
        Exit

    }

    Write-Header $rightsCollection[0].Requestor $rightsCollection[0].Target
    Write-Host ""

    $i = 0
    $mpr = $rightsCollection[$i]

    while ($i -lt $rightsCollection.Length)
    {

        $rightsSummary = $null
        $previousMPR = $mpr.MPR

        while ($mpr.MPR-eq $previousMPR)
        {

            $previousPerm = $mpr.Permission

            while ($mpr.Permission -eq $previousPerm -and $mpr.MPR -eq $previousMPR)
            {

                $previousAttrib = $mpr.Attribute

                $mpr = $rightsCollection[($i += 1)]

            }

            if ($rightsSummary -ne $null) {$rightsSummary += ", "}
            $rightsSummary += $previousPerm
            if ($previousAttrib -match 'All Attributes') {$rightsSummary += '*'}

        }

        "{0}   ({1})" -f $previousMPR, $rightsSummary

    }

}


# Provide full details showing requestor, target, MPRs, permissions and attributes

elseif ($Full -eq $true)
{

    if ($rightsCollection.Count -eq 0)
    {

        Write-Host "The requestor has no permissions on the target object"
        Exit

    }

    Write-Header $rightsCollection[0].Requestor $rightsCollection[0].Target

    $rightsCollection | Select-Object MPR,Permission,Attribute | Sort-Object -Property MPR | Format-Table -AutoSize -HideTableHeaders

}

# Just dump the PSObject so it can be queried further using PowerShell

else
{
    $rightsCollection
}