' XMRig Mining Dashboard - One-Click Launcher
' Double-click this file to start Dashboard with NO console windows

Dim shell, fso, scriptDir, dashboardPath, xmrigPath, xmrigExe

' Create objects
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get directories
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
dashboardPath = fso.BuildPath(scriptDir, "dashboard")
xmrigPath = "C:\XMRig\xmrig-6.22.0"
xmrigExe = fso.BuildPath(xmrigPath, "xmrig.exe")

' Check if XMRig is running, start it if not
On Error Resume Next
Set objWMI = GetObject("winmgmts:\\.\root\cimv2")
Set processes = objWMI.ExecQuery("SELECT * FROM Win32_Process WHERE Name = 'xmrig.exe'")

If processes.Count = 0 Then
    ' XMRig not running, start it
    If fso.FileExists(xmrigExe) Then
        shell.Run """" & xmrigExe & """", 0, False
        WScript.Sleep 3000 ' Wait 3 seconds for XMRig to start
    End If
End If
On Error Goto 0

' Launch dashboard with pythonw (no console window)
shell.CurrentDirectory = dashboardPath
shell.Run "pythonw.exe mining-dashboard.py", 0, False

' Exit immediately
Set shell = Nothing
Set fso = Nothing
WScript.Quit
