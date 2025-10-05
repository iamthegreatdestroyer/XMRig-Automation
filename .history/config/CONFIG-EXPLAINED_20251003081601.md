# XMRig Configuration Explained

This document explains the key settings in `config.json` and how they're optimized for your Ryzen 7 7730U.

## Core Settings

### CPU Configuration

```json
"cpu": {
    "enabled": true,
    "huge-pages": true,
    "max-threads-hint": 75,
    ...
}
```

- **enabled**: Enables CPU mining (required)
- **huge-pages**: Uses large memory pages for 10-20% performance boost
- **max-threads-hint: 75**: Uses 75% of available threads (12 of 16) to keep system responsive
- **asm**: true - Uses optimized assembly code for better performance
- **yield**: true - Allows other processes to use CPU when idle

### RandomX Optimization

```json
"randomx": {
    "mode": "auto",
    "1gb-pages": false,
    "numa": true,
    "scratchpad_prefetch_mode": 1
}
```

- **mode: auto**: Automatically selects best RandomX mode
- **numa: true**: Optimizes for NUMA architecture (important for Ryzen)
- **scratchpad_prefetch_mode: 1**: Hardware prefetching for better cache utilization

### Pool Configuration

```json
"pools": [{
    "algo": "rx/0",
    "coin": "monero",
    "url": "xmrpool.eu:3333",
    "keepalive": true,
    ...
}]
```

- **algo: rx/0**: RandomX algorithm for Monero
- **keepalive: true**: Maintains persistent connection to pool
- **retries: 5**: Attempts reconnection 5 times on failure
- **retry-pause: 5**: Waits 5 seconds between retries

### Background Mining

```json
"pause-on-battery": false,
"pause-on-active": false
```

- Continues mining even when on battery power
- Continues mining even when user is active (24/7 operation)

### Logging

```json
"log-file": "xmrig.log",
"print-time": 60,
"autosave": true
```

- Saves all output to xmrig.log
- Prints status every 60 seconds
- Auto-saves configuration changes

## Performance Tuning

### To Increase Hashrate (More Aggressive)

Change `max-threads-hint` from 75 to 85 or 90:

```json
"max-threads-hint": 85
```

⚠️ Warning: May make system less responsive

### To Decrease CPU Usage (More Conservative)

Change `max-threads-hint` from 75 to 50 or 60:

```json
"max-threads-hint": 60
```

💡 Recommended if you need to use PC while mining

### Expected Performance

- **Hashrate**: 1800-2000 H/s (with huge pages enabled)
- **CPU Usage**: ~75%
- **Temperature**: 65-75°C (depends on cooling)
- **Power Draw**: 35-45W

## Security Notes

1. **Wallet Address**: Your XMR wallet address is in plaintext - keep config.json secure
2. **Donation Level**: Set to 1% (default) - supports XMRig development
3. **API Disabled**: HTTP API is disabled by default for security

## Troubleshooting Config Issues

**Low Hashrate?**

- Enable huge pages (see configure-hugepages.ps1)
- Increase max-threads-hint to 85-90
- Check CPU temperature (thermal throttling)

**System Too Slow?**

- Decrease max-threads-hint to 50-60
- Enable pause-on-active (pauses when you use PC)

**Not Connecting to Pool?**

- Verify pool URL is correct
- Check firewall settings
- Try alternative pool: supportxmr.com:3333

## Advanced Settings

Most users should not modify these unless you know what you're doing:

- `randomx.init`: Dataset initialization threads (-1 = auto)
- `randomx.rdmsr/wrmsr`: MSR register access for performance tuning
- `cpu.priority`: Process priority (null = default)
- `dns.ttl`: DNS cache time-to-live

## Updating Configuration

After modifying config.json:

1. Stop mining: Run `stop-mining.bat`
2. Edit config.json
3. Start mining: Run `start-mining.bat`

Or use the provided scripts:

- `backup-config.ps1`: Backup before changes
- `update-xmrig.ps1`: Update XMRig while preserving config
