' Claude Ses simge uygulamasını konsol penceresi açmadan başlatır
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & dir & "\ClaudeSes.ps1""", 0, False
