# Sensors

`MeridianSensors` turns the machine into a `TelemetrySnapshot`. `LiveTelemetrySource.sample()` runs every sampler on one private
serial queue (HID and SMC reads run beside the rest), never touches the main actor, and fails soft: a missing symbol, key or
permission gives `nil` (or an empty list) for that metric, never a thrown error for the whole snapshot.

## Cadence

`LiveTelemetrySource(tiers:)` takes a `SamplingTiers` (defaults: GPU 2 s, temperatures 3 s, power 2 s, processes 3 s; CPU, memory, network, disks
and battery on every call; system info once). Between refreshes `sample()` returns each slow sampler's last result. Use `SamplingTiers.everyCall`
for one-shot tools and tests. At the defaults the full sampler costs about 1 % of one core in a release build (see the handoff for the measurement).

Rates are deltas between calls, so the first call returns zero rates and `power.source == "unavailable"`.
`LiveTelemetrySource.init()` queues a warm-up sample, and `meridianctl snapshot` takes a baseline and a second sample 0.7 s later.

## Where each metric comes from

| Section | Source | Private? | Notes |
| --- | --- | --- | --- |
| CPU total/user/system/perCore | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` tick deltas | no | 32-bit tick counters, wrapping subtraction. |
| CPU clusters | `sysctl hw.perflevel0.logicalcpu` (P), `hw.perflevel1.logicalcpu` (E) | no | Kernel lists E cores first; confirmed on M2 (see below). |
| Load, uptime | `getloadavg`, `sysctl kern.boottime` | no | Uptime includes sleep. |
| CPU frequency | not available | | Always `nil`; Apple silicon has no cheap unprivileged source. |
| Memory | `host_statistics64`, `hw.memsize`, `vm.swapusage`, `kern.memorystatus_vm_pressure_level` | no | Activity Monitor terms: used = app + wired + compressed, app = internal pages - purgeable, cached = file-backed + purgeable. |
| GPU | IORegistry `IOAccelerator` -> `PerformanceStatistics` "Device Utilization %" | no | Name from `model`, cores from `gpu-core-count`. Frequency is `nil`. |
| Disks | `getmntinfo`, `URL.resourceValues` (capacity, `volumeIsInternalKey`) | no | Free space uses "important usage" capacity (matches Finder). |
| Disk throughput | IORegistry `IOBlockStorageDriver` "Statistics" byte deltas | no | APFS volumes share a container, so the summed internal-drive rate is attributed to the boot disk. |
| Network | `SCDynamicStore` `State:/Network/Global/IPv4`, `getifaddrs` (`AF_LINK` 32-bit `if_data`, `AF_INET`) | no | Rates are for the primary interface only. No network calls; `publicIP` is always `nil`. |
| Wi-Fi | CoreWLAN `CWInterface.ssid()`, `transmitRate()` | no | SSID is `nil` without Location permission. Link speed falls back to `ifi_baudrate`. |
| Battery | `IOPSCopyPowerSourcesInfo`, IORegistry `AppleSmartBattery` | no | Health = `AppleRawMaxCapacity / DesignCapacity`. `Temperature` is hundredths of a degree C (verified: 3017 = 30.17 C). Watts = mA x mV / 1e6, negative while discharging. |
| Temperatures (HID) | `IOHIDEventSystemClient`, usage page 0xff00 usage 5 | **yes** | Resolved with `dlsym` from IOKit. |
| Temperatures and fans (SMC) | `AppleSMC` user client, selector 2, 80-byte `SMCParamStruct` | undocumented | Struct lives in `CMeridian.h`; calls are made from Swift. |
| Power | IOReport "Energy Model" deltas, SMC `PSTR` | **yes** | See below. |
| Processes | `proc_listallpids`, `proc_pid_rusage(RUSAGE_INFO_V4)`, `proc_name`, `proc_pidpath` | no | Top 8 by CPU. |
| Thermal pressure | `ProcessInfo.thermalState` | no | |
| System info | `sysctl machdep.cpu.brand_string`, `hw.model`, `hw.optional.arm64`, `ProcessInfo` | no | `hasNotch` is always `false` here; the app overrides it. |

### Private APIs and how they fail

All of these are looked up with `dlopen`/`dlsym` at runtime. If any symbol is missing, that sampler returns nothing.

- **HID temperatures**: `IOHIDEventSystemClientCreate`, `...SetMatching`, `...CopyServices`, `IOHIDServiceClientCopyProperty`,
  `IOHIDServiceClientCopyEvent`, `IOHIDEventGetFloatValue`. Service list is read once; an empty list is retried every 30 calls.
- **IOReport**: `IOReportCopyChannelsInGroup`, `IOReportCreateSubscription`, `IOReportCreateSamples`, `IOReportCreateSamplesDelta`,
  `IOReportChannelGetChannelName`, `IOReportSimpleGetIntegerValue`, `IOReportChannelGetUnitLabel`. On macOS 26 the library
  is `/usr/lib/libIOReport.dylib`; the old `PrivateFrameworks/IOReport.framework` path does not exist, so both are tried.
  Channels are read from the delta's `IOReportChannels` array rather than through `IOReportIterate`, which needs an
  Objective-C block. If no counter advances between two samples the result is `source: "unavailable"` with nil watts
  (or `source: "smc"` with only `totalWatts` when `PSTR` exists).
- **SMC**: `IOServiceOpen("AppleSMC")` works unprivileged for reads. Keys are enumerated once (`#KEY` count, command 8), and the
  live temperature keys (sane value, aliases removed) are re-read each tick; the list is rediscovered only if reads keep failing.

## Identifiers and names (for the UI)

- `TemperatureReading.id`: SMC sensors use the raw four-character key (`Tp01`); HID sensors use `hid:<Product>` (`hid:PMU tdie1`),
  with `#n` appended when several services share a product name. The prefix tells you the source.
- `name` is a display label from `SensorCatalog`: `SoC die 3`, `SoC device 2 (PMU2)`, `Battery 2`, `SSD channel 0`,
  `CPU core (Tp01)`, `GPU (Tg0f)`. Unknown keys fall back to the raw key. Intel placement names (`Palm Rest`, `Heatpipe 1`) are
  applied on Intel only, because the same keys mean something else on Apple silicon.
- Groups: HID names are grouped by substring (case-insensitive: cpu/pacc/eacc/tdie/soc, gpu, dram/memory, battery/gas gauge,
  nand/ssd, otherwise system). SMC keys are grouped by two-character prefix (`Tp`, `Te`, `TC` cpu; `Tg`, `TG` gpu; `Tm`, `TM` memory;
  `TB` battery; `TH` storage; the rest system).
- Values outside 0 < t <= 130 C are dropped. HID `tcal` (a calibration constant) is dropped.
- A chip publishes both HID and SMC sensors, so one group can hold many readings on different scales; prefer `hottest(in:)`
  for a headline number and see the handoff note about `average(of:)`.

## Tools

```
swift run meridianctl snapshot     # pretty JSON (default)
swift run meridianctl watch [n]    # one compact line per second, optional count
swift run meridianctl sensors      # temperatures: source, group, value, id, name
swift run meridianctl smc-keys     # every SMC key: type, size, decoded value, raw bytes, name
swift run meridianctl contribute [--out PATH]
```

## Contributing a chip mapping

Apple silicon SMC sensors differ per chip, and the catalog only names keys it is sure about.

1. Run `swift run meridianctl contribute` on your Mac. It writes `~/Desktop/meridian-sensors-<chip>.json`
   (use `--out PATH` for another file or directory) with the chip, model identifier, macOS version, every HID sensor
   (product, value, our name and group) and every SMC key (type, raw bytes, decoded value, our name and group).
   It contains no hostname, serial number or user data.
2. To improve names, compare readings under a known load (idle versus an all-core run) to see which keys track which cluster.
3. Add the entries to `SensorCatalog.swift` (`intelTemperatures` or `common`, or a new per-chip table) and a test that pins them,
   then open a pull request with the JSON attached under `docs/sensor-maps/`.
