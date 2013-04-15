' Slow Performance Checks.vbs
' Author: Alistair McMillan
' Start Date: 12 November 2012
' Version 2.1
' ----------------------------

Option Explicit

Const HKEY_LOCAL_MACHINE = &H80000002
Const HKEY_CURRENT_USER = &H80000001
const REG_SZ = 1
const REG_EXPAND_SZ = 2
const REG_BINARY = 3
const REG_DWORD = 4
const REG_MULTI_SZ = 7

Dim freePhysicalMemory, objSWbemLocator, objSWbemServices, objItem, colOSItems, _
	colItems, strComputer, WshShell, freeSpaceInPagingFiles, sizeStoredInPagingFiles, _
	strFilename, objFileSystem, objFile, strMachineName, objFSO, _
	objFolder, objSubFolders, objSubFolder, queriesFolder, objRegistry, _
	values, strValue, strValues, strKeyPath, strValueName, SchTasksCommand, _
	oExec, Line, servicePackeMajor, servicePackMinor, arrValueNames, arrValueTypes, _
	index, strOperatingSystem, strServiceParkMajor, strServiceParkMinor, strCurrentUser, _
	hasQueriesProblem, tempFolderTotal, temporaryInternetFolderTotal, queriesFolderTotal, _
	boolRemoteStartupItem, DataList

Set WshShell = CreateObject("WScript.Shell")

strComputer = InputBox("Enter full computer name (i.e. SWSA29565) or IP address")

If (IsNull(strComputer) Or IsEmpty(strComputer) Or Len(strComputer) < 1) Then

	Wscript.Echo "Can't continue without a machine name or IP address."

Else

	Set objSWbemLocator = CreateObject("WbemScripting.SWbemLocator")
	Set objSWbemServices = GetObject( "winmgmts://" & strComputer & "/root/cimv2" )
	objSWbemServices.Security_.ImpersonationLevel = 3

	' Get machine name to user for filename
	Set colItems = objSWbemServices.ExecQuery("select * from Win32_ComputerSystem")
	For Each objItem in colItems
		strMachineName = objItem.Name
	Next

	strFilename = strMachineName + " slow performance checks.txt"
	Set objFileSystem = CreateObject("Scripting.FileSystemObject")
	Set objFile = objFileSystem.OpenTextFile(strFilename, 8, True)

	objFile.WriteLine("")
	objFile.WriteLine("======================================================================")
	objFile.WriteLine("")
	objFile.WriteLine(" >> Slow Performance Checks.vbs - Alistair McMillan")
	objFile.WriteLine("[  ] Performing tests on " & strMachineName)
	objFile.WriteLine("[  ] Scan started at " & Now)
	objFile.WriteLine("")

	' Get page file sizes
	Set colOSItems = objSWbemServices.ExecQuery("select * from Win32_OperatingSystem")
	For Each objItem in colOSItems
		freePhysicalMemory = objItem.FreePhysicalMemory
		freeSpaceInPagingFiles = objItem.FreeSpaceInPagingFiles
		sizeStoredInPagingFiles = objItem.SizeStoredInPagingFiles
		strOperatingSystem = objItem.Caption
		strServiceParkMajor = objItem.ServicePackMajorVersion
		strServiceParkMinor = objItem.ServicePackMinorVersion
	Next

	' Basic info
	Set colItems = objSWbemServices.ExecQuery("select * from Win32_ComputerSystem")
	For Each objItem in colItems

		objFile.WriteLine("[  ] Operating System: " & strOperatingSystem)
		If ((strOperatingSystem = "Microsoft Windows XP Professional") And (strServiceParkMajor < 3)) Then
			objFile.WriteLine("[!!] Service Pack: " & strServiceParkMajor & "." & strServiceParkMinor)
		ElseIf ((strOperatingSystem = "Microsoft Windows 2000 Professional") And (strServiceParkMajor < 4)) Then
			objFile.WriteLine("[!!] Service Pack: " & strServiceParkMajor & "." & strServiceParkMinor)
		Else
			objFile.WriteLine("[  ] Service Pack: " & strServiceParkMajor & "." & strServiceParkMinor)
		End If		
		
		objFile.WriteLine("[  ] Domain: " & objItem.Domain )
		strCurrentUser = objItem.UserName
		objFile.WriteLine("[  ] User: " & objItem.UserName)
	Next

	objFile.WriteLine("")
	
	' CPU
	Set colItems = objSWbemServices.ExecQuery("Select * from Win32_Processor")
	For Each objItem in colItems
		If ((objItem.LoadPercentage > 90) Or (Round(objItem.CurrentClockSpeed/1000, 1) < 1)) Then
			objFile.Write("[!!] ")
		Else
			objFile.Write("[  ] ")
		End If		
		objFile.WriteLine(objItem.DeviceID & " - " & _
			"Clockspeed: " & Round(objItem.CurrentClockSpeed/1000, 1) & " GHz - " & _ 
			"Load: " & objItem.LoadPercentage & "% - " & _
			"Name: " & objItem.Name)
	Next

	objFile.WriteLine("")

	' RAM/Paging
	Set colItems = objSWbemServices.ExecQuery("select * from Win32_ComputerSystem")
	For Each objItem in colItems
		If (objItem.TotalPhysicalMemory/1024/1024 < 1024) Then
			objFile.WriteLine("[!!] RAM Total/Free: " & Round(objItem.TotalPhysicalMemory/1024/1024, 1) & "/" & Round(freePhysicalMemory/1024, 1) & " MB")
		Else
			objFile.WriteLine("[  ] RAM Total/Free: " & Round(objItem.TotalPhysicalMemory/1024/1024, 1) & "/" & Round(freePhysicalMemory/1024, 1) & " MB")
		End If
		objFile.WriteLine("[  ] Page File Total/Free: " & Round(sizeStoredInPagingFiles/1024, 1) & "/" & Round(freeSpaceInPagingFiles/1024, 1) & " MB")
	Next
	Set objRegistry = GetObject("winmgmts:\\" & strComputer & "\root\default:StdRegProv")
	strKeyPath = "SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
	strValueName = "PagingFiles"
	objRegistry.GetMultiStringValue HKEY_LOCAL_MACHINE, strKeyPath, strValueName, values
	For Each strValue in values
		If (IsNull(strValue)) Then
			objFile.WriteLine("[!!] No paging files key")
		Else
			If (InStr(strValue, " 0 0")) Then
				objFile.WriteLine("[  ] Virtual memory is SYSTEM MANAGED - " & strValue)
			Else
				objFile.WriteLine("[!!] Virtual memory is NOT system managed - " & strValue)
			End If
		End If
	Next

	objFile.WriteLine("")
	
	' Lists disks with total/free space
	Set colItems = objSWbemServices.ExecQuery("select * from Win32_LogicalDisk")
	For Each objItem in colItems
		If ("C:" = objItem.Name) Then
			If (IsNull(objItem.Size) Or IsNull(objItem.FreeSpace)) Then
				If (objItem.FreeSpace/objItem.Size < 10) Then
					objFile.Write("[!!] ")
				Else
					objFile.Write("[  ] ")
				End If
				objFile.WriteLine(objItem.Name & " " & objItem.FreeSpace/objItem.Size & " % - Total/Free Space: " & objItem.Size/1024/1024/1024 & " GB / " & objItem.FreeSpace/1024/1024/1024 & " GB")
			else
				If (Round((objItem.FreeSpace/objItem.Size)*100, 1) < 10) Then
					objFile.Write("[!!] ")
				Else
					objFile.Write("[  ] ")
				End If
				objFile.WriteLine(objItem.Name & " " & Round((objItem.FreeSpace/objItem.Size)*100, 1) & " % - " & " Total/Free Space: " & Round(objItem.Size/1024/1024/1024, 2) & " GB / " & Round(objItem.FreeSpace/1024/1024/1024, 2) & " GB ")
			End If
		End If
	Next

	objFile.WriteLine("")
	
	objFile.WriteLine("RUNNING PROCESSES")
	objFile.WriteLine("-----------------")
	
	' RAM
	objFile.WriteLine(vbTab & " WORKING   PAGE FILE   PROCESS")
	objFile.WriteLine(vbTab & " SET (MB), USAGE (MB), NAME         , COMMAND")
	
	' Creating disconnected recordset to hold data
	Const adVarChar = 200
	Const MaxCharacters = 255
	Set DataList = CreateObject("ADOR.Recordset")
	DataList.Fields.Append "WorkingSetSize", adVarChar, MaxCharacters
	DataList.Fields.Append "PageFileUsage", adVarChar, MaxCharacters
	DataList.Fields.Append "Name", adVarChar, MaxCharacters
	DataList.Fields.Append "CommandLine", adVarChar, MaxCharacters
	DataList.Open
	
	' Retrieve list of processes and load into recordset
	Set colItems = objSWbemServices.ExecQuery("select * from Win32_Process")
	For Each objItem in colItems
		DataList.AddNew
		DataList("WorkingSetSize") = objItem.WorkingSetSize
		DataList("PageFileUsage") = objItem.PageFileUsage
		DataList("Name") = objItem.Name
		' Because command line can sometimes be null and recordsets don't like null values
	'	If (IsNull(objItem.CommandLine)) Then
	'		DataList("CommandLine") = "-"
	'	Else
	'		DataList("CommandLine") = objItem.CommandLine
	'	End If
		DataList.Update
	Next
	DataList.Sort = "WorkingSetSize DESC"
	DataList.MoveFirst
	Do Until DataList.EOF
		objFile.Write("[  ]  ")
		If (Round(DataList.Fields.Item("WorkingSetSize")/1024/1024, 2) < 1000) Then
			objFile.Write(" ")
		End If
		If (Round(DataList.Fields.Item("WorkingSetSize")/1024/1024, 2) < 100) Then
			objFile.Write(" ")
		End If
		If (Round(DataList.Fields.Item("WorkingSetSize")/1024/1024, 2) < 10) Then
			objFile.Write(" ")
		End If
		objFile.Write(FormatNumber(Round(DataList.Fields.Item("WorkingSetSize")/1024/1024, 2), 2, -1))
		objFile.Write(",    ")
		If (Round(DataList.Fields.Item("PageFileUsage")/1024/1024, 2) < 1000) Then
			objFile.Write(" ")
		End If
		If (Round(DataList.Fields.Item("PageFileUsage")/1024/1024, 2) < 100) Then
			objFile.Write(" ")
		End If
		If (Round(DataList.Fields.Item("PageFileUsage")/1024/1024, 2) < 10) Then
			objFile.Write(" ")
		End If
		objFile.WriteLine(FormatNumber(Round(DataList.Fields.Item("PageFileUsage")/1024/1024, 2), 2, -1) & ", " & DataList.Fields.Item("Name") & ", " & DataList.Fields.Item("CommandLine") )
		DataList.MoveNext
	Loop
'	For Each objItem in colItems
'		objFile.Write("[  ]  ")
'		If (Round(objItem.WorkingSetSize/1024/1024, 2) < 1000) Then
'			objFile.Write(" ")
'		End If
'		If (Round(objItem.WorkingSetSize/1024/1024, 2) < 100) Then
'			objFile.Write(" ")
'		End If
'		If (Round(objItem.WorkingSetSize/1024/1024, 2) < 10) Then
'			objFile.Write(" ")
'		End If
'		objFile.Write(FormatNumber(Round(objItem.WorkingSetSize/1024/1024, 2), 2, -1))
'		objFile.Write(",    ")
'		If (Round(objItem.PageFileUsage/1024/1024, 2) < 1000) Then
'			objFile.Write(" ")
'		End If
'		If (Round(objItem.PageFileUsage/1024/1024, 2) < 100) Then
'			objFile.Write(" ")
'		End If
'		If (Round(objItem.PageFileUsage/1024/1024, 2) < 10) Then
'			objFile.Write(" ")
'		End If
'		objFile.WriteLine(FormatNumber(Round(objItem.PageFileUsage/1024/1024, 2), 2, -1) & ", " & objItem.Name & ", " & objItem.CommandLine )
'	Next
	
	objFile.WriteLine("")

	objFile.WriteLine("SCHEDULED TASKS")
	objFile.WriteLine("---------------")

	SchTasksCommand = "schtasks /query /v /FO TABLE /s " & strMachineName
	Set oExec = WshShell.Exec(SchTasksCommand)

'	On Error Resume Next
	Do While oExec.StdOut.AtEndOfStream <> True
		Line = oExec.StdOut.ReadLine
		If Not IsNull(Line) Then
			objFile.WriteLine(Line)
		End If
	Loop

	objFile.WriteLine("")
	
	objFile.WriteLine("MACHINE STARTUP ITEMS")
	objFile.WriteLine("---------------------")

	Set objRegistry = GetObject("winmgmts:\\" & strComputer & "\root\default:StdRegProv")
	strKeyPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
	objRegistry.EnumValues HKEY_LOCAL_MACHINE, strKeyPath, arrValueNames, arrValueTypes
	For index=0 To UBound(arrValueNames)
		Select Case arrValueTypes(index)
			Case REG_SZ
				objRegistry.GetStringValue HKEY_LOCAL_MACHINE, strKeyPath, arrValueNames(index), strValue
				if(InStr(1, strValue, "\\") > 0) Then
					boolRemoteStartupItem = True
					objFile.Write("[!!] ")
				Else
					objFile.Write("[  ] ")
				End If
				objFile.WriteLine arrValueNames(index) & ",  " & strValue
			Case REG_EXPAND_SZ
				objRegistry.GetStringValue HKEY_LOCAL_MACHINE, strKeyPath, arrValueNames(index), strValue
				if(InStr(1, strValue, "\\") > 0) Then
					boolRemoteStartupItem = True
					objFile.Write("[!!] ")
				Else
					objFile.Write("[  ] ")
				End If
				objFile.WriteLine arrValueNames(index) & ",  " & strValue
			Case REG_BINARY
				' Should never reach here
			Case REG_DWORD
				' Should never reach here
			Case REG_MULTI_SZ
				' Should never reach here
		End Select 
	Next
	
	objFile.WriteLine("")
	
	objFile.WriteLine("USER STARTUP ITEMS")
	objFile.WriteLine("------------------")

	Set objRegistry = GetObject("winmgmts:\\" & strComputer & "\root\default:StdRegProv")
	strKeyPath = "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
	If (IsNull(strCurrentUser)) Then
		objFile.WriteLine "No user currently logged in"
	Else
		objRegistry.EnumValues HKEY_CURRENT_USER, strKeyPath, arrValueNames, arrValueTypes
		On Error Resume Next
		For index=0 To UBound(arrValueNames)
			Select Case arrValueTypes(index)
				Case REG_SZ
					objRegistry.GetStringValue HKEY_CURRENT_USER, strKeyPath, arrValueNames(index), strValue
					if(InStr(1, strValue, "\\") > 0) Then
						boolRemoteStartupItem = True
						objFile.Write("[!!] ")
					Else
						objFile.Write("[  ] ")
					End If
					objFile.WriteLine arrValueNames(index) & ",  " & strValue
				Case REG_EXPAND_SZ
					objRegistry.GetStringValue HKEY_CURRENT_USER, strKeyPath, arrValueNames(index), strValue
					if(InStr(1, strValue, "\\") > 0) Then
						boolRemoteStartupItem = True
						objFile.Write("[!!] ")
					Else
						objFile.Write("[  ] ")
					End If
					objFile.WriteLine arrValueNames(index) & ",  " & strValue
				Case REG_BINARY
					' Should never reach here
				Case REG_DWORD
					' Should never reach here
				Case REG_MULTI_SZ
					' Should never reach here
			End Select 
		Next
		On Error Goto 0
	End If
	
	objFile.WriteLine("")

	objFile.WriteLine("TEMP FOLDERS")
	objFile.WriteLine("------------")
	objFile.WriteLine("FOLDER SIZE (MB), FOLDER NAME")

	If objFileSystem.FolderExists("\\" & strComputer & "\c$\windows\temp") Then
		Set queriesFolder = objFileSystem.GetFolder("\\" & strComputer & "\c$\windows\temp")
		On Error Resume Next
		tempFolderTotal = tempFolderTotal + Round(queriesFolder.Size/1024/1024, 1)
		objFile.WriteLine("[  ] " & Round(queriesFolder.Size/1024/1024, 1) & "MB, <" & queriesFolder.Path & ">")
		On Error Goto 0
	End If

	If objFileSystem.FolderExists("\\" & strComputer & "\c$\temp") Then
		Set queriesFolder = objFileSystem.GetFolder("\\" & strComputer & "\c$\temp")
		On Error Resume Next
		tempFolderTotal = tempFolderTotal + Round(queriesFolder.Size/1024/1024, 1)
		objFile.WriteLine("[  ] " & Round(queriesFolder.Size/1024/1024, 1) & "MB, <" & queriesFolder.Path & ">")
		On Error Goto 0
	End If

	If objFileSystem.FolderExists("\\" & strComputer & "\c$\windows\system32\config\systemprofile\local settings\temp") Then
		Set queriesFolder = objFileSystem.GetFolder("\\" & strComputer & "\c$\windows\system32\config\systemprofile\local settings\temp")
		On Error Resume Next
		tempFolderTotal = tempFolderTotal + Round(queriesFolder.Size/1024/1024, 1)
		objFile.WriteLine("[  ] " & Round(queriesFolder.Size/1024/1024, 1) & "MB, <" & queriesFolder.Path & ">")
		On Error Goto 0
	End If

	Set objFolder = objFileSystem.GetFolder("\\" & strComputer & "\C$\documents and settings")
	Set objSubFolders = objFolder.SubFolders
	For Each objSubFolder in objSubFolders
		If objFileSystem.FolderExists("\\" & strComputer & "\c$\documents and settings\" & objSubFolder.name & "\local settings\temp") Then
			Set queriesFolder = objFileSystem.GetFolder("\\" & strComputer & "\c$\documents and settings\" & objSubFolder.name & "\local settings\temp")
			On Error Resume Next
			tempFolderTotal = tempFolderTotal + Round(queriesFolder.Size/1024/1024, 1)
			objFile.WriteLine("[  ] " & Round(queriesFolder.Size/1024/1024, 1) & "MB, <" & queriesFolder.Path & ">")
			On Error Goto 0
		End If
	Next

	If (tempFolderTotal > 1024) Then
		objFile.WriteLine("[!!] " & tempFolderTotal & "MB in Temp Folders - they should be checked and cleared")
	Else
		objFile.WriteLine("[  ] " & tempFolderTotal & "MB in Temp Folders - OK")
	End If
		
	objFile.WriteLine("")

	objFile.WriteLine("TEMPORARY INTERNET FOLDERS")
	objFile.WriteLine("--------------------------")
	objFile.WriteLine("FOLDER SIZE (MB), FOLDER NAME")

	If objFileSystem.FolderExists("\\" & strComputer & "\c$\windows\system32\config\systemprofile\local settings\temporary internet files") Then
		Set queriesFolder = objFileSystem.GetFolder("\\" & strComputer & "\c$\windows\system32\config\systemprofile\local settings\temporary internet files")
		On Error Resume Next
		temporaryInternetFolderTotal = temporaryInternetFolderTotal + Round(queriesFolder.Size/1024/1024, 1)
		objFile.WriteLine("[  ] " & Round(queriesFolder.Size/1024/1024, 1) & "MB, <" & queriesFolder.Path & ">")
		On Error Goto 0
	End If

	Set objFolder = objFileSystem.GetFolder("\\" & strComputer & "\C$\documents and settings")
	Set objSubFolders = objFolder.SubFolders
	For Each objSubFolder in objSubFolders
		If objFileSystem.FolderExists("\\" & strComputer & "\c$\documents and settings\" & objSubFolder.name & "\local settings\temporary internet files") Then
			Set queriesFolder = objFileSystem.GetFolder("\\" & strComputer & "\c$\documents and settings\" & objSubFolder.name & "\local settings\temporary internet files")
			On Error Resume Next
			temporaryInternetFolderTotal = temporaryInternetFolderTotal + Round(queriesFolder.Size/1024/1024, 1)
			objFile.WriteLine("[  ] " & Round(queriesFolder.Size/1024/1024, 1) & "MB, <" & queriesFolder.Path & ">")
			On Error Goto 0
		End If
	Next

	If (temporaryInternetFolderTotal > 1024) Then
		objFile.WriteLine("[!!] " & temporaryInternetFolderTotal & "MB in Temporary Internet Folders - they should be checked and cleared")
	Else
		objFile.WriteLine("[  ] " & temporaryInternetFolderTotal & "MB in Temporary Internet Folders - OK")
	End If
		
	objFile.WriteLine("")

	objFile.WriteLine("QUERIES FOLDERS")
	objFile.WriteLine("---------------")
	objFile.WriteLine("FOLDER SIZE (MB), FOLDER NAME")

	Set objFolder = objFileSystem.GetFolder("\\" & strComputer & "\C$\documents and settings")
	Set objSubFolders = objFolder.SubFolders
	For Each objSubFolder in objSubFolders
		If objFileSystem.FolderExists("\\" & strComputer & "\c$\documents and settings\" & objSubFolder.name & "\application data\microsoft\queries") Then
			Set queriesFolder = objFileSystem.GetFolder("\\" & strComputer & "\c$\documents and settings\" & objSubFolder.name & "\application data\microsoft\queries")
			On Error Resume Next
			queriesFolderTotal = queriesFolderTotal + Round(queriesFolder.Size/1024/1024, 1)
			If (Round(queriesFolder.Size/1024/1024, 1) > 1) Then
				hasQueriesProblem = True
			End If
			objFile.WriteLine("[  ] " & Round(queriesFolder.Size/1024/1024, 1) & "MB, <" & queriesFolder.Path & ">")
			On Error Goto 0
		End If
	Next
	
	If (hasQueriesProblem) Then
		objFile.WriteLine("[!!] " & queriesFolderTotal & "MB TOTAL - folders should be cleared and Excel fix may need to be applied")
	Else
		objFile.WriteLine("[  ] " & queriesFolderTotal & "MB TOTAL")
	End If
		
	SchTasksCommand = "notepad.exe " & strFilename
	WshShell.Exec(SchTasksCommand)

End If
	
Wscript.Quit
