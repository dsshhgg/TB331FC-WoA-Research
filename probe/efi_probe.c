// Minimal AArch64 UEFI application probe for TB331FC BDS chainload test.
// Prints one line on ConOut and halts. Subsystem 10, machine 0xAA64.
typedef unsigned short CHAR16;
typedef unsigned long long UINTN;
typedef unsigned long long UINT64;

typedef struct {
  char  Hdr[24];
  void *FirmwareVendor;
  unsigned int FirmwareRevision;
  void *ConIn;
  void *ConOut;
  void *StdErr;
  void *RuntimeServices;
  void *BootServices;
} EFI_SIMPLE_TEXT_OUTPUT_INTERFACE_PARTIAL, EFI_SYSTEM_TABLE_PARTIAL;

/* Minimal text-out protocol prefix: Reset, OutputString are the first two members
   after the 8-byte vtable pointer in the protocol struct. */
typedef struct {
  UINT64    Reset;
  UINT64    OutputString;
} SIMPLE_TEXT_OUT_VTABLE;

typedef struct {
  SIMPLE_TEXT_OUT_VTABLE *Vtbl;
} SIMPLE_TEXT_OUT;

extern void (*OutputStringFn)(SIMPLE_TEXT_OUT *, CHAR16 *);

static void puts16(SIMPLE_TEXT_OUT *out, const CHAR16 *s)
{
  typedef UINT64 (*fn_t)(SIMPLE_TEXT_OUT *, const CHAR16 *);
  fn_t f = (fn_t)out->Vtbl->OutputString;
  f(out, s);
}

static const CHAR16 msg1[] = u"TB331FC-BDS-EFI-PROBE-OK\r\n";
static const CHAR16 msg2[] = u"If you can read this, BDS loaded our EFI app.\r\n";

UINT64 efi_main(void *imageHandle, EFI_SYSTEM_TABLE_PARTIAL *st)
{
  SIMPLE_TEXT_OUT *out = (SIMPLE_TEXT_OUT *)st->ConOut;
  if (out && out->Vtbl && out->Vtbl->OutputString) {
    puts16(out, msg1);
    puts16(out, msg2);
  }
  for (;;) {
    __asm__ __volatile__("wfe");
  }
  return 0;
}