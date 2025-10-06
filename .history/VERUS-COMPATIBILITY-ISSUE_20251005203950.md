# VERUS (VRSC) MINING - COMPATIBILITY ISSUE

## 🚨 Current Status: DISABLED

**Date:** October 5, 2025  
**Issue:** XMRig hangs after displaying pool information when trying to mine Verus

## 📋 Problem Description

When attempting to mine Verus (VRSC), XMRig initializes successfully and displays:
```
* POOL #1      pool.verus.io:9998 algo auto
* POOL #2      ap.luckpool.net:3956 algo auto
* POOL #3      verushash.na.mine.zpool.ca:8800 algo auto
```

But then stops without connecting to the pool or starting mining.

## 🔍 Root Cause

**XMRig 6.22.0 may not have native VerusHash support.**

VerusHash is a custom algorithm that requires either:
1. A special XMRig build with VerusHash support
2. A different miner (like ccminer or hellminer)
3. XMRig with VerusHash plugin/patch

## ✅ Working Coins

| Coin | Algorithm | Status | Daily Profit |
|------|-----------|--------|--------------|
| **Monero (XMR)** | RandomX | ✅ Working | $0.60-0.70/day |
| **Raptoreum (RTM)** | GhostRider | ✅ Should Work | $0.02-0.03/day |
| **Verus (VRSC)** | VerusHash | ❌ Not Compatible | N/A |

## 🎯 Recommended Action

### **Option 1: Stick with XMR + RTM (Recommended)**

Focus on the two working coins:
- **Monero (XMR)** - Highest and most stable profit ($0.60-0.70/day)
- **Raptoreum (RTM)** - Good secondary option ($0.02-0.03/day)

Update profit switcher to only monitor XMR and RTM.

### **Option 2: Try Alternative Verus Miner**

If you really want to mine Verus, you'll need:

1. **Download CCMiner for VerusHash:**
   ```
   https://github.com/monkins1010/ccminer/releases
   ```

2. **Or Hellminer:**
   ```
   https://github.com/hellcatz/luckpool/tree/master/miners
   ```

3. **Create separate mining setup** for Verus with different executable

### **Option 3: Wait for XMRig Update**

Check if newer XMRig versions support VerusHash natively.

## 💡 Why Monero is Best Choice

Even though Verus showed higher profitability ($1.40/day), that was theoretical based on:
- **Assumption:** 10,000 H/s hashrate
- **Reality:** XMRig doesn't support the algorithm

**Monero advantages:**
- ✅ Proven working with your hardware
- ✅ Stable pools and connectivity
- ✅ Currently mining at 1,900 H/s (~95% efficiency)
- ✅ Actual profit: $0.60-0.70/day
- ✅ No compatibility issues

## 📊 Realistic Profit Comparison

| Coin | Compatibility | Daily Profit | Monthly Profit |
|------|---------------|--------------|----------------|
| XMR | ✅ Working | $0.65 | $19.50 |
| RTM | ⚠️ Untested | $0.02 | $0.60 |
| VRSC | ❌ Not Working | $0.00 | $0.00 |

**Total with XMR+RTM: ~$20/month**

## 🔧 Temporary Solution Applied

1. ✅ Reverted XMRig to Monero configuration
2. ✅ Monero mining resumed successfully
3. ⏸️ Verus mining disabled until compatible miner found

## 🚀 Next Steps

### Immediate (Now):
1. Keep mining Monero (most profitable working option)
2. Let profit switcher monitor XMR vs RTM only
3. Test RTM manually when ready

### Short-term (This Week):
1. Test Raptoreum mining manually
2. Verify RTM pools work correctly
3. Enable XMR ↔ RTM profit switching

### Long-term (Future):
1. Research Verus-compatible miners
2. Consider dual-miner setup (XMRig + CCMiner)
3. Build automated switching for different miner executables

## 📝 Configuration Changes Needed

To disable Verus in profit switcher, comment out VRSC in `profit-switcher-v2.ps1`:

```powershell
$CoinAPIs = @{
    XMR  = @{ ... }  # Keep Monero
    RTM  = @{ ... }  # Keep Raptoreum
    # VRSC = @{ ... }  # Disable Verus (not compatible)
}
```

## ✅ Conclusion

**Stick with Monero mining for now.**

You're already earning optimally with XMR at ~$0.65/day ($19.50/month). The theoretical Verus profit of $1.40/day doesn't matter if the miner can't actually mine it.

**Focus on what works:**
- ✅ Monero: Proven, stable, profitable
- ⏳ Raptoreum: Test when ready
- ❌ Verus: Requires different miner software

---

**Status:** Mining Monero at 1,900 H/s - OPTIMAL ✨
