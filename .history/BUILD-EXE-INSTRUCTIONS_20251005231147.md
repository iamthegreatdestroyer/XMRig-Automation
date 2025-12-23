# 📦 HOW TO BUILD STANDALONE .EXE - MANUAL INSTRUCTIONS

## ✅ PyInstaller is now installed!

The PyInstaller package is successfully installed on your system.

---

## 🚀 Build the .EXE (Takes 2-3 minutes)

### **Option 1: Run the build script**

1. **Close VS Code completely** (so it doesn't interrupt the build)
2. Open PowerShell **as Administrator**
3. Run these commands:

```powershell
cd C:\Users\sgbil\XMRig-Automation
.\BUILD-DASHBOARD-EXE.ps1
```

4. Wait 2-3 minutes for the build to complete
5. Executable will be created at: `C:\Users\sgbil\XMRig-Automation\dist\XMRig-Dashboard.exe`

---

### **Option 2: Manual build command**

If the script doesn't work, run this manually:

```powershell
cd C:\Users\sgbil\XMRig-Automation\dashboard

pyinstaller `
    --onefile `
    --windowed `
    --name "XMRig-Dashboard" `
    --distpath "C:\Users\sgbil\XMRig-Automation\dist" `
    --hidden-import PyQt6.QtCore `
    --hidden-import PyQt6.QtGui `
    --hidden-import PyQt6.QtWidgets `
    --hidden-import psutil `
    --clean `
    mining-dashboard.py
```

---

## ⏱️ What Happens During Build

1. **[0-30s]** PyInstaller analyzes dependencies
2. **[30s-2min]** Bundles Python + PyQt6 + dashboard code
3. **[2-3min]** Creates standalone .exe file (~50-80 MB)

You'll see output like:
```
INFO: PyInstaller: 6.16.0
INFO: Python: 3.13.7
INFO: Platform: Windows-10-...
INFO: wrote C:\...\XMRig-Dashboard.spec
...
INFO: Building EXE from EXE-00.toc completed successfully.
```

---

## ✅ After Build Completes

The executable will be at:
**`C:\Users\sgbil\XMRig-Automation\dist\XMRig-Dashboard.exe`**

### To use it:

**Option A: Double-click the .exe**
- Just double-click `XMRig-Dashboard.exe`
- Dashboard opens immediately
- No Python needed!

**Option B: Create desktop shortcut**
1. Right-click `XMRig-Dashboard.exe`
2. Send to → Desktop (create shortcut)
3. Rename to "XMRig Mining Dashboard"

**Option C: Copy to other PCs**
- Copy the .exe file to any Windows 10/11 PC
- Double-click to run
- Works without Python installation!

---

## 🎯 Benefits of the .EXE

- ✅ **No Python needed** - Runs on any Windows PC
- ✅ **No dependencies** - Everything bundled in one file
- ✅ **Easy distribution** - Share with friends/family
- ✅ **Clean installation** - Just copy and run
- ✅ **Professional** - Looks like a real app

---

## 🐛 If Build Fails

### Error: "Permission Denied"
- Run PowerShell as Administrator
- Close antivirus temporarily

### Error: "Module not found"
- Install dependencies first:
```powershell
pip install PyQt6 psutil
```

### Error: "PyInstaller not found"
- Reinstall:
```powershell
python -m pip install --upgrade pyinstaller
```

### Build succeeds but .exe doesn't work
- The .exe must be in the dist folder
- XMRig must be at: `C:\XMRig\xmrig-6.22.0\`
- Edit paths in dashboard code if needed

---

## 💡 Alternative: Use the VBS Launcher

If you don't want to build the .exe, the **VBS launcher works perfectly!**

Just use:
- Desktop shortcut: "XMRig Mining Dashboard"
- Or: `C:\Users\sgbil\XMRig-Automation\XMRig-Dashboard.vbs`

**This is already working and requires no build!**

---

## 📝 Summary

### For personal use:
✅ **Use the desktop shortcut** - Already working, no build needed!

### To share with others or run on PCs without Python:
📦 **Build the .exe** - Run `BUILD-DASHBOARD-EXE.ps1` outside VS Code

### Current status:
- ✅ PyInstaller: Installed
- ✅ Dashboard: Working
- ✅ VBS Launcher: Ready to use
- ⏳ .EXE Build: Optional, ready when you want it

---

**The easiest option: Just use the desktop shortcut! It's already working perfectly.** 🎉

*Last updated: October 5, 2025*
