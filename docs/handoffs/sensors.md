# Handoff: Sensors

## What I built

`LiveTelemetrySource.sample()` returns a populated `TelemetrySnapshot` on this M2 MacBook Air (macOS 26.5.1).

- `Sources/CMeridian/include/CMeridian.h`: 80-byte `SMCParamStruct` (and sub-structs) with a `_Static_assert`, selector and command constants,
  accessors for the `bytes[32]` field. No private declarations: those are resolved in Swift with `dlsym`.
- `Sources/MeridianSensors/`, one file per sampler: `CPUSampler`, `MemorySampler`, `GPUSampler`, `DiskSampler`, `NetworkSampler`,
  `BatterySampler`, `HIDTemperatureSampler`, `SMCConnection` + `SMCDecoder` + `SMCSampler` (temperatures, fans, `PSTR`),
  `PowerSampler` (IOReport), `ProcessSampler`, `SystemInfoSampler` (system info and thermal pressure), `SensorCatalog`,
  `SensorProbe` (public diagnostics for the CLI), `IORegistry` and `Sysctl` helpers, `LiveTelemetrySource` (engine, serial queue).
- `Sources/meridianctl/`: `snapshot`, `watch [n]`, `sensors`, `smc-keys`, `contribute [--out PATH]`, hand-rolled argv.
- `Tests/MeridianSensorsTests/`: 17 Swift Testing tests (decoder fixtures, catalog, struct size, units, live smoke, latency).
- `docs/SENSORS.md`.
- No `Package.swift` change: CoreWLAN and SystemConfiguration autolink through their modules.

## Verified (all with `--scratch-path .build/sensors`)

`./scripts/test.sh --scratch-path .build/sensors --filter MeridianSensorsTests`:
`Test run with 17 tests in 4 suites passed after 2.112 seconds.`
Latency test output: `sample() latency over 5 calls: mean 0.0687 seconds, worst 0.0697 seconds` (debug build, while other agents
were compiling on the same machine; HID events are ~50 ms of that and the floor, SMC reads run in parallel with them).
A release `meridianctl watch 6` used about 0.37 s of CPU in total, startup included.

`swift run --scratch-path .build/sensors meridianctl watch 4` (second sample onward, machine under build load):
```
cpu 75% (u 51% s 24%) | mem 78% normal | gpu 47% | net en0 down 9.3 KB/s up 9.3 KB/s | disk r 54 MB/s w 1.0 MB/s | bat 75%+ 11.2W | cpuT 81C | max 105C | therm fair | power ioreport cpu 9.5W gpu 0.7W tot 18.5W | top swift-frontend 98%
cpu 59% (u 45% s 14%) | mem 79% normal | gpu 41% | net en0 down 15 KB/s up 81 KB/s | disk r 63 MB/s w 12 MB/s | bat 75% -5.2W | cpuT 77C | max 100C | therm fair | power ioreport cpu 6.8W gpu 0.8W tot 14.6W | top swift-frontend 90%
```
Network and disk rates are non-zero from the second line; power comes from IOReport.

`meridianctl snapshot` (quiet machine, sensors abbreviated): battery `cycleCount 104, healthFraction 0.9156, temperatureC 30.36,
watts +8.9 (charging), adapterWatts 30, minutesRemaining 183`; gpu `Apple M2, 8 cores, utilization 0.20`; network `en0, 192.168.0.105,
linkSpeedMbps 130`; power `ioreport cpu 0.25 W gpu 0.23 W ane 0 W total 10.3 W`; memory `used 13.17 GB of 17.18 GB, swap 0.77 of 2.15 GB`;
system `Apple M2, Mac14,2, 26.5.1, isAppleSilicon true`; thermal `149 sensors, fans [], pressure fair`.

`meridianctl sensors`: 149 readings. 33 HID (`PMU tdie1-8` and `PMU2 tdie1-8` cpu, `PMU tdev` system, six `gas gauge battery`, `NAND CH0 temp`
storage) plus SMC (`Tp**` x 25, `Te04-06`, `TCHP`, `TCMb`, `TCMz`, `Tg0e..Tg0r`, `Tm0B`, `TMVR`, `TB0T-TB2T`, `TH0T`, `TH0x`, `Th**`, `Ts**`).
`meridianctl smc-keys | head`: `#KEY ui32 1630`, then `AC-B si8 -1`, `AC-C flag 0`, ... ; 1474 of 1630 keys readable.
`meridianctl contribute --out <scratchpad>`: `wrote ...meridian-sensors-apple-m2.json: 33 HID sensors, 1474 SMC keys` (I did not write to the Desktop).

Core ordering (item 1): `ioreg -p IODeviceTree -n cpus` lists `cluster-type` "E" for logical cpu 0-3 and "P" for 4-7, and
`hw.perflevel0/1.logicalcpu` are both 4 here. So per-core data is E cores first, matching `CPUMetrics.efficiencyCores`. At light load cores 0-3
sat at 18-25% while cores 4-7 sat at 0-4%, consistent with that. Only M2 verified.

## nil or empty on this machine, and why

- `cpu.frequencyMHz`, `gpu.frequencyMHz`: no cheap unprivileged source on Apple silicon.
- `thermal.fans`: empty. The M2 Air is fanless (`FNum` absent), so this is correct.
- `network.wifiSSID`: nil without Location permission (expected). `publicIP`: nil by design.
- `battery.minutesRemaining`: nil when plugged in and not charging, and while the system is still estimating.
- `power.aneWatts` reads 0 W when the Neural Engine is idle (not nil).
- Per-volume disk throughput: only the boot disk gets the internal-drive rate.

## Surprising

- **IOReport path**: on macOS 26 `/System/Library/PrivateFrameworks/IOReport.framework/IOReport` does not exist, so the path in the brief fails with
  "no such file, not in dyld cache". The library is `/usr/lib/libIOReport.dylib`. `PowerSampler` tries both.
- **`kernel_task` is missing from the process list.** `proc_pid_rusage(0)` returns EPERM for an unprivileged process, so there is no CPU number
  for pid 0. Everything else, including root-owned daemons, works. The brief's "exclude pid 0 but include kernel_task" is contradictory (kernel_task is pid 0).
- **HID names on M2**: no `pACC`/`eACC` sensors. M2 exposes `PMU tdie1-8`, `PMU2 tdie1-8`, `PMU tdev1-8`, `PMU2 tdev`, `gas gauge battery` x6,
  `NAND CH0 temp`. `PMU tcal` is a constant and is filtered.
- **SMC keys on Apple silicon**: the Intel names for `Ts0P` (Palm Rest) or `Th0H` (Heatpipe) are meaningless there, so the Intel table is applied on Intel only.
- `proc_listallpids` returns a pid count, not bytes.
- Memory "used" follows Activity Monitor (app + wired + compressed) and "cached" is file-backed plus purgeable, not inactive, as that matches what users see.
- `ioft` and `flt` are decoded little-endian (host order). The `ioft` decoder is tested with a fixture only; no fan key exists here to confirm it on hardware.

## What the UI should know

- `average(of: .cpu)` mixes SMC `Tp**` (per-core-cluster, about 55-66 C here at light load, over 100 C under full load) with HID `PMU tdie` (about 57-63 C).
  Use `hottest(in:)` for a headline, or filter by id prefix (`hid:` vs bare 4-character key) for a consistent scale. I did not change
  `MeridianKit`. A `source` field on `TemperatureReading` would be a clean addition.
- There are ~149 readings: group or collapse them in lists. Names are unique per snapshot.
- `power.source` is `"ioreport"`, `"smc"` (total only) or `"unavailable"`. `totalWatts` prefers SMC `PSTR` (whole system) over CPU+GPU+ANE.
- `system.macOSVersion` is the bare version ("26.5.1"); prefix "macOS" in the UI.
- `battery.isPresent == false` is returned on desktop Macs (not a nil battery).
- The first `sample()` after launch has zero rates and no power; the app should expect that once.
- Missing from `MeridianKit` models: nothing blocking. Wishes: `TemperatureReading.source`, `NetworkMetrics` per-interface list.

## Not done

- No Intel hardware to test, so Intel paths (`TC0P` names, `TG0P`, fans, `fpe2` fan decode) are unit-tested only.
- `IOReportIterate` is not used (see docs). No per-core frequency, no per-process GPU, no discrete-GPU memory.
- Nothing committed or staged.
