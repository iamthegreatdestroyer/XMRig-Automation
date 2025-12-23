# 🚀 XMRig Mining Dashboard - One-Click Launcher

## Quick Start

### **Option 1: Desktop Shortcut (EASIEST)** ⭐

1. Look for **"XMRig Mining Dashboard"** shortcut on your desktop
2. **Double-click it**
3. Done! Dashboard opens automatically

**What it does:**

- ✅ Checks if XMRig is running
- ✅ Starts XMRig if needed (hidden in background)
- ✅ Opens the Mining Dashboard GUI
- ✅ NO console windows!

---

### **Option 2: VBScript Launcher**

Double-click: `XMRig-Dashboard.vbs`

- Silent launch, no console windows
- Perfect for taskbar pinning

---

### **Option 3: Batch File**

Double-click: `XMRig-Dashboard.bat`

- Classic Windows launcher
- Flashes briefly then hides

---

### **Option 4: PowerShell Launcher**

Right-click → Run with PowerShell: `LAUNCH-ONE-CLICK.ps1`

- Full control version
- Shows error messages if something fails

---

## 📦 Build Standalone Executable (Optional)

Want a **single .exe file** with everything bundled?

Run: `.\BUILD-DASHBOARD-EXE.ps1`

This creates:

- `dist\XMRig-Dashboard.exe` - Standalone executable (~50MB)
- Desktop shortcut automatically
- **NO Python installation needed on other computers!**

Perfect for:

- Running on multiple PCs
- Sharing with friends
- Clean installations

---

## 🎯 Features

### Mining Dashboard Shows:

- 📊 **Real-time Hashrate** (10s/60s/15m averages)
- ✅ **Share Statistics** (accepted/rejected)
- 💰 **Earnings Calculator** (hourly/daily/weekly/monthly)
- 🖥️ **System Resources** (CPU, Memory, Temps)
- 📝 **Live Log Viewer** (last 20 lines)
- ⚙️ **Pool & Algorithm Info**
- 🔄 **Auto-refresh** every 2 seconds

### Dashboard Theme:

- 🌑 Dark cyberpunk design
- 💚 Matrix-green accents (#00ff41)
- 📱 Clean, modern interface

---

## 🔧 Technical Details

### Files Explained:

| File                            | Purpose                                |
| ------------------------------- | -------------------------------------- |
| `XMRig-Dashboard.vbs`           | VBScript launcher (silent, no console) |
| `XMRig-Dashboard.bat`           | Batch file launcher (classic)          |
| `LAUNCH-ONE-CLICK.ps1`          | PowerShell launcher (checks XMRig)     |
| `CREATE-DESKTOP-SHORTCUT.ps1`   | Creates desktop shortcut               |
| `BUILD-DASHBOARD-EXE.ps1`       | Builds standalone .exe                 |
| `dashboard/mining-dashboard.py` | Main dashboard application             |

### Requirements:

- ✅ Python 3.11+ (for .py and .ps1 launchers)
- ✅ PyQt6 (auto-installed by START-DASHBOARD.ps1)
- ✅ psutil (auto-installed)
- ✅ XMRig running at `C:\XMRig\xmrig-6.22.0`

**Note:** The standalone .exe (Option 2) needs **NO Python** installation!

---

## 🐛 Troubleshooting

### Dashboard won't open?

1. **Check Python:** Run `python --version` in terminal
   - Should show Python 3.11 or newer
2. **Install dependencies:** Run `.\START-DASHBOARD.ps1` once
3. **Check XMRig path:** Edit `LAUNCH-ONE-CLICK.ps1` if your XMRig is elsewhere

### Dashboard shows no data?

1. **Check XMRig is running:** Look for `xmrig.exe` in Task Manager
2. **Check log file:** Should exist at `C:\XMRig\xmrig-6.22.0\xmrig.log`
3. **Check log is fresh:** File should update every 60 seconds

### Error messages?

- **"XMRig not found"** → Update path in `LAUNCH-ONE-CLICK.ps1` line 9
- **"Dashboard script not found"** → Run from correct directory
- **"Python not found"** → Install Python from python.org

---

## 📍 Customization

### Change XMRig Path:

Edit `LAUNCH-ONE-CLICK.ps1`:

```powershell
$XMRIG_PATH = "C:\Your\Custom\Path\xmrig"
```

### Change Icon:

Edit `CREATE-DESKTOP-SHORTCUT.ps1`:

```powershell
$shortcut.IconLocation = "C:\Your\Custom\Icon.ico"
```

### Auto-start on Windows Boot:

1. Press `Win+R`
2. Type: `shell:startup`
3. Copy `XMRig Mining Dashboard.lnk` to that folder

---

## 🎨 Dashboard Preview

```
╔═══════════════════════════════════════════════════════╗
║     XMRig Mining Dashboard v1.0 - Monero (XMR)      ║
╠═══════════════════════════════════════════════════════╣
║                                                       ║
║  STATUS: 🟢 XMRig is MINING                          ║
║                                                       ║
║  ┌─────────────────────────────────────────────────┐ ║
║  │ Hashrate: 1,899.50 H/s                          │ ║
║  │ Detail: 1,901.2 / 1,899.5 / 1,905.0 H/s        │ ║
║  │                                                  │ ║
║  │ Shares: 120 accepted / 0 rejected              │ ║
║  │ Difficulty: 72000                               │ ║
║  │                                                  │ ║
║  │ Earnings: $0.13/hr | $3.08/day | $92.40/mo    │ ║
║  └─────────────────────────────────────────────────┘ ║
║                                                       ║
║  ┌─────────────────────────────────────────────────┐ ║
║  │ CPU: 98.2% | Memory: 27.8 / 31.3 GB (88.9%)   │ ║
║  │ Temp: 72°C | Pool: pool.hashvault.pro:3333    │ ║
║  └─────────────────────────────────────────────────┘ ║
║                                                       ║
║  [Live Log - Last 20 lines]                          ║
║  ┌─────────────────────────────────────────────────┐ ║
║  │ [22:18:04] speed 10s/60s/15m 1899.5 1901.2... │ ║
║  │ [22:18:15] accepted (121/0) diff 72000         │ ║
║  │ [22:18:20] new job from pool.hashvault.pro...  │ ║
║  └─────────────────────────────────────────────────┘ ║
║                                                       ║
║  Last updated: 2025-10-05 22:18:25 (2 seconds ago)  ║
╚═══════════════════════════════════════════════════════╝
```

---

## 📝 Notes

- Dashboard reads from `C:\XMRig\xmrig-6.22.0\xmrig.log`
- Updates every **2 seconds** automatically
- XMR price fetched from CoinGecko API
- Earnings based on current network difficulty
- Lightweight: ~50MB RAM usage

---

## 🚀 Future Enhancements

- [ ] Multi-coin support
- [ ] Historical charts (24hr/7day graphs)
- [ ] Email/SMS alerts for offline mining
- [ ] Remote monitoring (web dashboard)
- [ ] Overclocking profiles
- [ ] Pool auto-switching

---

## 📄 License

Personal use. Part of XMRig-Automation suite.

Created: October 2025
Version: 1.0

---

**Enjoy your mining! ⛏️💎**
