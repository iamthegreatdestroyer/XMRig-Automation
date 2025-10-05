# Troubleshooting Guide

## Quick Diagnostics

### Check Mining Status
```powershell
# Run the status checker
.\scripts\check-status.ps1
```

### Common Symptoms & Solutions

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| Mining not starting | Task not configured | Run create-scheduled-task.ps1 |
| Low hashrate | Huge pages disabled | Enable huge pages, restart PC |
| XMRig quarantined | Windows Defender | Run configure-defender.ps1 |
| No shares accepted | Internet/pool issue | Check connection, try different pool |
| High CPU usage | Thread count too high | Lower max-threads-hint in config |
| System unresponsive | All threads used | Stop mining, lower thread count |

---

## Installation Issues

### Error: "Administrator privileges required"

**Cause**: Script needs elevated permissions

**Solution**:
1. Close PowerShell
2. Right-click PowerShell → Run as Administrator
3. Run script again

### Error: "Execution policy prevents script"

**Cause**: PowerShell execution policy restriction

**Solution**:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then run the script again.

### Error: "Cannot download XMRig from GitHub"

**Causes**:
- No internet connection
- Firewall blocking GitHub
- GitHub API rate limit

**Solutions**:
1. Check internet connection
2. Temporarily disable firewall
3. Wait 1 hour and try again
4. Manual download:
   - Go to https://xmrig.com/download
   - Download Windows 64-bit version
   - Extract to C:\XMRig

### Installation fails at Windows Defender configuration

**Cause**: Insufficient permissions or antivirus conflict

**Solution - Manual Defender Exclusion**:
1. Open Windows Security
2. Virus & threat protection
3. Manage settings
4. Exclusions → Add or remove exclusions
5. Add exclusion → Folder
6. Browse to C:\XMRig
7. Repeat for Process → xmrig.exe

---

## Startup & Auto-Start Issues

### Mining doesn't start automatically on boot

**Check scheduled task**:
1. Win + R → `taskschd.msc`
2. Find "XMRig Auto Start"
3. Verify status is "Ready"
4. Check "Triggers" tab shows "At startup"
5. Check "Actions" tab points to correct script

**If task missing**:
```powershell
cd C:\XMRig-Automation\setup
.\create-scheduled-task.ps1 -TaskName "XMRig Auto Start" -ScriptPath "C:\XMRig-Automation\scripts\start-mining.bat" -XMRigPath "C:\XMRig"
```

**Test task manually**:
1. In Task Scheduler, right-click task
2. Click "Run"
3. Check if XMRig starts

### Task Scheduler error: "The system cannot find the file specified"

**Cause**: Incorrect paths in scheduled task

**Solution**:
1. Delete existing task
2. Verify script paths are correct
3. Re-run create-scheduled-task.ps1 with correct paths

### Mining starts then immediately stops

**Check logs**:
```batch
cd C:\XMRig
type xmrig.log
```

**Common errors**:
- "bind failed": Config file error
- "no valid pools": Wrong pool URL or wallet address
- "OpenCL disabled": Normal, ignore (we use CPU only)
- "FAILED TO APPLY MSR MOD": Normal, reduces hashrate slightly

---

## Performance Issues

### Hashrate much lower than 1800 H/s

**Target**: 1800-2000 H/s for AMD Ryzen 7 7730U

**Diagnostics**:

1. **Check huge pages status**:
   - Look in XMRig output for "huge pages"
   - Should show: "READY (huge pages 100%)"
   - If not: Run configure-hugepages.ps1, then restart PC

2. **Check CPU temperature**:
   ```powershell
   .\scripts\monitor-performance.ps1
   ```
   - Temperature > 85°C = thermal throttling
   - Solution: Improve cooling, clean dust

3. **Check thread utilization**:
   - Open config.json
   - Verify: `"max-threads-hint": 75`
   - Try increasing to 85 or 90 for higher hashrate

4. **Check for background processes**:
   - Open Task Manager
   - Sort by CPU usage
   - Close unnecessary programs

### Hashrate keeps fluctuating wildly

**Normal fluctuations**: ±5-10% is expected

**Excessive fluctuations** (±20%+):

**Causes & Solutions**:
- **Windows Update installing**: Wait for completion
- **Antivirus scanning**: Schedule scans when not mining
- **Thermal throttling**: Improve cooling
- **Power settings**: Set to "High Performance"

**Set High Performance power plan**:
1. Control Panel → Power Options
2. Select "High Performance"
3. Or: `powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`

### System becomes unresponsive while mining

**Cause**: Too many threads used, no CPU left for system

**Solution 1: Lower thread count**:
1. Stop mining: `stop-mining.bat`
2. Edit C:\XMRig\config.json
3. Change `"max-threads-hint": 75` to `50` or `60`
4. Start mining: `start-mining.bat`

**Solution 2: Pause mining when active** (not recommended for 24/7):
```json
"pause-on-active": true  // Change from false to true
```

---

## Connection Issues

### Error: "connect error" or "connection refused"

**Causes**:
- Pool is down
- Firewall blocking
- Wrong pool URL
- Internet connection problem

**Solutions**:

1. **Test internet connection**:
   ```powershell
   Test-Connection -ComputerName xmrpool.eu -Count 4
   ```

2. **Try alternative pool**:
   Edit config.json, change URL to:
   - `supportxmr.com:3333`
   - `minexmr.com:4444`
   - `hashvault.pro:3333`

3. **Check firewall**:
   - Windows Firewall → Allow an app
   - Add C:\XMRig\xmrig.exe
   - Allow both Private and Public networks

4. **Check antivirus**: May be blocking network access

### No shares accepted / "all shares rejected"

**Check wallet address**:
1. Open C:\XMRig\config.json
2. Verify wallet address is correct
3. Should be 95 characters for Monero

**Check pool compatibility**:
- Algorithm must be "rx/0" (RandomX)
- Pool must support Monero
- Some pools require registration

**Test with known-good config**:
- Temporarily use pool: supportxmr.com:3333
- Use your wallet address
- If works: Original pool has issue

---

## Windows Defender / Antivirus Issues

### Windows Defender keeps deleting xmrig.exe

**Permanent solution**:
```powershell
cd C:\XMRig-Automation\setup
.\configure-defender.ps1 -XMRigPath "C:\XMRig"
```

**Manual exclusion**:
1. Windows Security
2. Virus & threat protection
3. Manage settings
4. Exclusions → Add an exclusion
5. Add folder: C:\XMRig
6. Add process: xmrig.exe

**Restore quarantined file**:
1. Windows Security
2. Virus & threat protection
3. Protection history
4. Find xmrig.exe
5. Actions → Restore

### Third-party antivirus blocking XMRig

**Avast/AVG**:
1. Settings → General → Exceptions
2. Add exception for C:\XMRig

**Norton**:
1. Settings → Antivirus → Scans and Risks
2. Exclusions/Low Risks → Configure
3. Add folder: C:\XMRig

**Bitdefender**:
1. Protection → View Features → Antivirus
2. Settings → Manage Exceptions
3. Add: C:\XMRig

**Kaspersky**:
1. Settings → Additional → Threats and Exclusions
2. Manage Exclusions → Add
3. Add folder: C:\XMRig

---

## Huge Pages Issues

### Huge pages not working / showing 0%

**Symptoms in XMRig output**:
- "READY (huge pages 0%)"
- "allocated 2080 MB (0 huge pages, 0%)"

**Most common cause**: Haven't restarted after configuration

**Solution**:
1. Run configure-hugepages.ps1
2. **Restart computer** (required!)
3. Start mining
4. Check output for "huge pages 100%"

### Error: "SeLockMemoryPrivilege failed"

**Cause**: User doesn't have "Lock pages in memory" privilege

**Solution**:
```powershell
cd C:\XMRig-Automation\setup
.\configure-hugepages.ps1
```

**Manual configuration** (if script fails):
1. Win + R → `gpedit.msc`
2. Navigate to: Computer Configuration → Windows Settings → Security Settings → Local Policies → User Rights Assignment
3. Double-click "Lock pages in memory"
4. Add your user account
5. Restart computer

**Note**: Windows Home edition doesn't have gpedit.msc. Huge pages may not work on Home edition.

---

## Process Issues

### Can't stop mining / xmrig.exe won't close

**Force stop**:
```powershell
Stop-Process -Name "xmrig" -Force
```

**Or use Task Manager**:
1. Ctrl + Shift + Esc
2. Find xmrig.exe
3. Right-click → End Task

### Multiple xmrig.exe processes running

**Cause**: Auto-restart loop + manual start

**Solution**:
```batch
# Stop all instances
taskkill /F /IM xmrig.exe
# Then start properly
start-mining.bat
```

### CPU usage showing more than configured

**Explanation**: CPU % in Task Manager is total CPU time, not per-core

**Example with 16 threads, 75% config**:
- Uses 12 of 16 threads
- Task Manager shows: 75% CPU (correct!)
- This is expected behavior

---

## Configuration Issues

### Error: "failed to load config"

**Causes**:
- Syntax error in config.json
- Missing quotes or commas
- Invalid JSON format

**Solution**:
1. Use JSON validator: https://jsonlint.com
2. Copy-paste your config.json
3. Fix any errors highlighted
4. Or restore from backup: C:\XMRig-Automation\config\config.json

### Mining to wrong wallet address

**Verify address**:
1. Open C:\XMRig\config.json
2. Find: `"user": "YOUR_WALLET_ADDRESS"`
3. Confirm it's YOUR wallet, not the default

**Change wallet address**:
1. Stop mining
2. Edit config.json → `"user"` field
3. Save file
4. Start mining

---

## Hardware Issues

### CPU temperature too high (>85°C)

**Immediate action**:
1. Stop mining: `stop-mining.bat`
2. Let computer cool down

**Permanent solutions**:
- **Clean dust**: From fans, heatsinks, vents
- **Improve airflow**: Open case, add fans
- **Reapply thermal paste**: If CPU >2 years old
- **Lower thread count**: Reduce to 50-60%
- **Underclock CPU**: Use BIOS or Ryzen Master

**Set temperature monitoring**:
Edit monitoring/alert-config.json:
```json
"maxTemperature": 80  // Alert at 80°C instead of 85°C
```

### System crashes or freezes while mining

**Possible causes**:
- Overheating
- Insufficient power supply
- RAM instability
- CPU instability

**Diagnostics**:
1. Check Event Viewer for crash logs:
   - Win + R → `eventvwr.msc`
   - Windows Logs → System
   - Look for Critical errors

2. Test RAM:
   ```powershell
   # Windows Memory Diagnostic
   mdsched.exe
   ```

3. Stress test CPU (without mining):
   - Download Prime95
   - Run blend test for 1 hour
   - If crashes: Hardware issue, not mining-specific

**Solutions**:
- Lower thread count to 50%
- Check PSU wattage is sufficient
- Test RAM modules individually
- Update BIOS

---

## Pool Dashboard Issues

### Can't see my miner on pool dashboard

**Wait time**: New miners take 5-10 minutes to appear

**Check**:
1. Visit https://xmrpool.eu/#/dashboard
2. Enter your wallet address
3. Look under "Active Miners"

**If not appearing after 15 minutes**:
- Verify mining is actually running
- Check shares are being accepted in logs
- Confirm wallet address matches exactly

### Dashboard shows 0 hashrate

**Causes**:
- Just started mining (wait 10 minutes)
- Network issues
- Pool not receiving shares

**Solution**:
1. Check status: `.\scripts\check-status.ps1`
2. Verify "Accepted Shares" is increasing
3. Wait 10-15 minutes for pool to update
4. If still 0: Check connection issues (see above)

---

## Uninstallation Issues

### Can't delete XMRig folder

**Cause**: xmrig.exe is still running

**Solution**:
```powershell
# Stop process
Stop-Process -Name "xmrig" -Force

# Wait a moment
Start-Sleep -Seconds 2

# Then delete
Remove-Item -Path "C:\XMRig" -Recurse -Force
```

### Scheduled task still exists after uninstall

**Manual removal**:
1. Win + R → `taskschd.msc`
2. Find "XMRig Auto Start"
3. Right-click → Delete

**Or via PowerShell**:
```powershell
Unregister-ScheduledTask -TaskName "XMRig Auto Start" -Confirm:$false
```

---

## Advanced Diagnostics

### Enable debug logging

Edit config.json:
```json
"verbose": 1,  // Or 2 for even more detail
"log-file": "xmrig-debug.log"
```

### Check actual CPU threads in use

In XMRig log, look for:
```
| THREADS | 12       | maximum efficiency
```

Should match: 16 threads × 75% = 12 threads

### Test configuration without mining

```batch
cd C:\XMRig
xmrig.exe --config=config.json --dry-run
```

---

## Getting Help

### Collect diagnostic information

Before asking for help, collect:

1. **Setup log**:
   ```
   C:\XMRig-Automation\setup-log.txt
   ```

2. **XMRig log** (last 100 lines):
   ```batch
   cd C:\XMRig
   powershell "Get-Content xmrig.log -Tail 100"
   ```

3. **System info**:
   ```powershell
   systeminfo > systeminfo.txt
   ```

4. **Status output**:
   ```powershell
   .\scripts\check-status.ps1 > status.txt
   ```

### Where to get help

- **Documentation**: Check docs folder
- **XMRig docs**: https://xmrig.com/docs
- **Monero mining**: r/MoneroMining
- **XMRig GitHub**: https://github.com/xmrig/xmrig/issues

---

## Emergency Recovery

### Complete reset

```powershell
# 1. Stop everything
Stop-Process -Name "xmrig" -Force

# 2. Remove scheduled task
Unregister-ScheduledTask -TaskName "XMRig Auto Start" -Confirm:$false

# 3. Delete installation
Remove-Item -Path "C:\XMRig" -Recurse -Force

# 4. Start fresh
cd C:\XMRig-Automation
.\MASTER-SETUP.ps1
```

### Restore from backup

```powershell
cd C:\XMRig-Automation\tools
.\backup-config.ps1  # Creates backup

# To restore:
Copy-Item "backup\config.json" -Destination "C:\XMRig\config.json"
```

---

**Still having issues?** Check [`docs/FAQ.md`](FAQ.md) or XMRig documentation at https://xmrig.com/docs
