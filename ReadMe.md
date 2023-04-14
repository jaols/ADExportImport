# Active Directory Export & Import

## Introduction
This solution is intended for creating Active Directory (AD) content on a development platform using an existing other Active Dirtectory as source. It is **NOT** a backup/restore process and will **NOT** create identical objects at the target AD. **But you will get** a complete set of objects with most AD-attributes set from the source AD  transformed to fit the target environment.

This first version support the following AD-objects:
- Organizational units (OU:s)
- Users
- Groups

The supported AD-attributes (or AD-properties) is determined by `json` settings file and attribute limitations. The `ntSecurityDescriptor` was part of the solution but generated to much overhead due to the inherited ACE:s.

The objects data is saved as `json` files. These `json` files will be in a generic form with replacement placeholders for substition during the import process.

## Why
Because we want a fast way of populating an AD with close-to-reality data from another source AD.
Because we want to select a subset of objects from source the AD.
Because we want to be able to transform the source data to fit a target AD.
Becasue it is not possible to use ADFS or any other replication service for this scenario.
Because we don't want to purchase a full service solution at this time. We just want to populate objects.

## Requirements
The solution is based on the PSJumpStart module found in [Powershell Gallery](https://www.powershellgallery.com/packages/PSJumpStart) or [GitHub](https://github.com/jaols/PSJumpStart/tree/master/PSJumpStart).

The PowerShell [Active Directory Module](https://learn.microsoft.com/en-us/powershell/module/activedirectory/?view=windowsserver2022-ps)

## Installation
Install the PSJumpStart module from [Powershell Gallery](https://www.powershellgallery.com/packages/PSJumpStart) and install the [Active Directory Module](https://4sysops.com/wiki/how-to-install-the-powershell-active-directory-module/)

Download the files from this repository to computers that is member of the source and target AD respectively.

## Usage
The process is done in the following steps:
1. Copy the `Example for Export domain.json` file to th name of the source domain. `Contoso.json` according to sample.
2. Edit the export `json` file to limit export scope.
3. Run PowerShell export scripts for each wanted object type
4. Copy the resulting `json` files to the target AD computer
5. Copy the  `Example for Import domain.json` file to the name of the target domain. `DevContoso.json` according to the sampla
6. Run PowerShell import scripts for each wanted object type to import `json`data files in logical order (OU first).
7. Run PowerShell import scripts again with the `-SetProperties` option.

The import process is done in two steps as the first will create empty objects that may be used as property content during the `-SetProperty` process. For instance users need to be in place to get group membership.

### Test run
It is recomended to use the `-LDAPfilter` option for export scripts to get a limited number of objects as a test for export and import.

### The export and import setting `json` files
The content in the setting files are actually used for default input arguments to the `ps1` files. This is a standard feature provided by [PSJumpStart](https://github.com/jaols/PSJumpStart/tree/master/PSJumpStart). The provided setting files are separated for export and import, but it is possible to use only one file and rename it to current AD domain name if no special Replacements is needed.

The provided example files includes these standard argument settings:
|Setting|Description|
|-------|-----------|
|`Replacements`|Extra replacement entries or fixed replacement entries for generic data replacements|
|`ExportPaths`|Generic representation of OU paths to export objects from source AD|
|`ExportOuProperties`|List of property names to export when exporting OU objects|
|`ExportGroupProperties`|List of property names to export when exporting group objects|
|`ExportUserProperties`|List of property names to export when exporting user objects|
|`ExportExcludeAttributes`||List of property names to **exclude** from export (of limited use)|
|`ExcludePrincipals`|For future use with `ntSecurityDescriptor` export/import|
|`StandardUserPassword`|Password to use for each created user. It is possible to use the setting `(New-RandomPassword -PaswordLength 12)` to get a password at runtime.|
|`ImportExcludeAttributes`|List of properties to exclude from the import data (the target AD may be missing some attributes)|

You may add more default arguments to the setting files. It is also possible to have separated settings for each `ps1` file or a combination (see [PSJumpStart](https://github.com/jaols/PSJumpStart/tree/master/PSJumpStart) for details).

### A few words on `Replacements`
One of the key features in this solution is the use of a set of replacment strings to use for generating generic data export files. These replacments need to be translated to new values at the target AD. 

The following standard replacements are supported by the function `Get-ReplaceStrings`:
- DNSroot <-> `(Get-ADDomain).DNSroot`
- DomainSID <-> `(Get-ADDomain).DomainSID`
- DomainLDAP <-> `(Get-ADDomain).distinguishedName`
- Domain <-> `(Get-ADDomain).NetBIOSname + "\"`
- CompanyName <-> `(Get-ADDomain).Name`

The default tag for replacments is `¤` so the string `¤DomainLDAP¤` is replaced by `DC=Contoso, DC=com` (for Contoso domain). Default replacements will be overwritten by `Replacments` from `json` settings file.

The order of the replacement content is important as you do not want to replace domain short name before the DomainLDAP.

### Resulting `json` data file
The standard file name is , but you may change this by using the script argument
Some words on the resulting `json` data files. 

## Down the rabbit hole
Well some times you just need to dive in:
- The member list for a group will be cleaned from non-existing principals before used in `Import-AdGroups.ps1`. 
- It is possible to change the tag character for generic data marking. This is done in `.\LocalLib\ConvertTo-GenericStrings.ps1` **AND**  `.\LocalLib\ConvertFrom-GenericStrings.ps1`
- The `.\LocalLib\Get-StandardExludeAttributes.ps1` contains a static set of ExcludeAttributres. 

## Known issues
A version based on ADSI of the export process may be in the making for use on a Windows client without the ActiveDirectory module.

Support for non-inherited access in `ntSecurityDescriptor` is also probably in the cards for the future.

This is the first version, so please report suggestions and/or improvements.