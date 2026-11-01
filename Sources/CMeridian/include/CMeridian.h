// CMeridian: C declarations for IOKit structures used by the Sensors workstream.
// Keep everything here plain C so SwiftPM can build it without Xcode. Private symbols
// (HID sensors, IOReport) are resolved with dlsym in Swift, so they need no declarations here.
#ifndef CMERIDIAN_H
#define CMERIDIAN_H
#include <stdint.h>
#include <stdbool.h>

// The SMC speaks one fixed 80-byte struct through IOConnectCallStructMethod. The layout below is the
// classic one shared by every SMC tool since 2006; natural C alignment yields exactly 80 bytes, which the
// static assert guards because a wrong size makes the kernel reject the call with no useful error.
typedef struct {
    uint8_t  major, minor, build, reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version, length;
    uint32_t cpuPLimit, gpuPLimit, memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t  dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t       key;
    SMCVersion     vers;
    SMCPLimitData  pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t        result;
    uint8_t        status;
    uint8_t        data8;
    uint32_t       data32;
    uint8_t        bytes[32];
} SMCParamStruct;

_Static_assert(sizeof(SMCParamStruct) == 80, "SMCParamStruct must be 80 bytes");

// IOConnectCallStructMethod selector and sub-commands carried in SMCParamStruct.data8.
enum {
    kMeridianSMCUserClientSelector = 2,
    kMeridianSMCReadBytes   = 5,
    kMeridianSMCReadKeyByIndex = 8,
    kMeridianSMCReadKeyInfo = 9,
};

// Swift imports fixed C arrays as 32-element tuples; these accessors avoid that awkwardness.
static inline uint8_t *meridian_smc_bytes(SMCParamStruct *p) { return p->bytes; }
static inline int meridian_smc_struct_size(void) { return (int)sizeof(SMCParamStruct); }

#endif
