' ========================================
' XMRig Miner Launcher (Standalone)
' ========================================
' Starts XMRig mining without dashboard
' Runs silently in background
' Auto-restarts if crashed
' ========================================

Option Explicit

Dim shell, fso, scriptPath, xmrigPath, xmrigExe, batFile
Dim processes, isRunning

' Create objects
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get script directory
scriptPath = fso.GetParentFolderName(WScript.ScriptFullName)

' Define XMRig paths
xmrigPath = "C:\XMRig\xmrig-6.22.0"
xmrigExe = xmrigPath & "\xmrig.exe"
batFile = scriptPath & "\scripts\start-mining.bat"

' Check if XMRig is already running
Set processes = GetObject("winmgmts:\\.\root\cimv2").ExecQuery("SELECT * FROM Win32_Process WHERE Name = 'xmrig.exe'")
isRunning = (processes.Count > 0)

If isRunning Then
    ' Already running
    MsgBox "XMRig is already running!" & vbCrLf & vbCrLf & _
           "Check your system tray or Task Manager.", _
           vbInformation, "XMRig Mining"
Else
    ' Start XMRig
    If fso.FileExists(batFile) Then
        ' Use the auto-restart batch file if available
        shell.Run """" & batFile & """", 0, False
    ElseIf fso.FileExists(xmrigExe) Then
        ' Start XMRig directly
        shell.CurrentDirectory = xmrigPath
        shell.Run """" & xmrigExe & """", 0, False
    Else
        ' Error - XMRig not found
        MsgBox "XMRig not found!" & vbCrLf & vbCrLf & _
               "Please install XMRig to:" & vbCrLf & _
               xmrigPath, _
               vbCritical, "Error"
        WScript.Quit 1
    End If
    
    ' Give it a moment to start
    WScript.Sleep 2000
    
    ' Verify it started
    Set processes = GetObject("winmgmts:\\.\root\cimv2").ExecQuery("SELECT * FROM Win32_Process WHERE Name = 'xmrig.exe'")
    If processes.Count > 0 Then
        MsgBox "XMRig mining started successfully!" & vbCrLf & vbCrLf & _
               "Mining is running in the background.", _
               vbInformation, "XMRig Mining"
    Else
        MsgBox "Failed to start XMRig!" & vbCrLf & vbCrLf & _
               "Check Windows Defender exclusions or run as Administrator.", _
               vbExclamation, "Warning"
    End If
End If

' Cleanup
Set processes = Nothing
Set fso = Nothing
Set shell = Nothing
