# nix-sel4-example

A working [seL4 Microkit](https://docs.sel4.systems/projects/microkit/) system you can clone and boot. Built with [nix-sel4](https://github.com/conao3/nix-sel4).

```sh
git clone https://github.com/conao3/nix-sel4-example
cd nix-sel4-example
nix run
```

```
LDR|INFO: loader for seL4 starting
...
Booting all finished, dropped to user space
MON|INFO: Microkit Monitor started!
main: hello from a Nix-built seL4 system
```

Quit QEMU with `Ctrl-A` then `x`.

Nothing else is needed: no SDK download, no `aarch64-none-elf` toolchain to install, no `MICROKIT_SDK` to point anywhere, and no seL4 hardware. QEMU emulates the target, so this runs on any `x86_64-linux` or `aarch64-linux` machine with Nix and flakes enabled.

## What is here

```
flake.nix        the whole system: which board, which protection domains, how they connect
src/main/main.c  the one protection domain
```

`flake.nix` does three things:

1. `buildProtectionDomain` cross-compiles `src/main` against the Microkit SDK for the chosen board.
2. `mkSystemDescription` renders the system description that the `microkit` tool consumes. It is written as a Nix attribute set instead of XML, so a mapping into a memory region that does not exist, two mappings that overlap, or a channel to an unknown protection domain fail during evaluation.
3. `buildSystem` runs the `microkit` tool and returns the bootable image plus a QEMU runner.

## Commands

```sh
nix run              # boot under QEMU
nix flake check      # boot and assert the greeting reaches the console
nix build .#image    # result/loader.img, for flashing to real hardware
nix build .#report   # result/report.txt, the kernel object and memory allocation
nix develop          # microkit, the cross toolchains, QEMU and MICROKIT_SDK on PATH
```

## Changing the target board

Edit `board` near the top of `flake.nix`. `qemu_virt_aarch64`, `qemu_virt_aarch64_el1` and `qemu_virt_riscv64` boot with `nix run`; the other 25 boards in [nix-sel4's board table](https://github.com/conao3/nix-sel4/blob/master/lib/boards.nix) build an image you flash yourself.

```nix
board = "qemu_virt_riscv64";
```

Keep `config = "debug"` while you are working. `microkit_dbg_puts` writes through a kernel debug call that the release build compiles out, so a release system stays silent until you give it a real serial driver.

## Adding a second protection domain

The point of Microkit is that programs live in separate protection domains and reach each other only through what the system description grants. Here is the full change to split the greeting across two domains: `main` writes into a shared page and signals, `logger` reads and prints.

Add `src/logger/logger.c`:

```c
#include <stdint.h>
#include <microkit.h>

uintptr_t shared_vaddr;
uint64_t main_channel;

void init(void)
{
}

void notified(microkit_channel ch)
{
    if (ch != (microkit_channel)main_channel) {
        return;
    }

    microkit_dbg_puts("logger: ");
    microkit_dbg_puts((const char *)shared_vaddr);
    microkit_dbg_puts("\n");
}
```

Replace `src/main/main.c` with:

```c
#include <stdint.h>
#include <microkit.h>

uintptr_t shared_vaddr;
uint64_t logger_channel;

static void copy_string(char *dst, const char *src)
{
    while ((*dst++ = *src++) != '\0') {
    }
}

void init(void)
{
    copy_string((char *)shared_vaddr, "hello from a Nix-built seL4 system");
    microkit_notify((microkit_channel)logger_channel);
}

void notified(microkit_channel ch)
{
}
```

Neither file hardcodes an address or a channel number. `shared_vaddr`, `logger_channel` and `main_channel` are patched into the ELF by the `microkit` tool from the `setvarVaddr` and `setvarId` entries below. `setvar` targets are word sized, which is why the channel identifiers are `uint64_t` rather than `microkit_channel`.

In `flake.nix`, build the second domain alongside the first:

```nix
      logger = microkitTools.buildProtectionDomain {
        name = "logger";
        inherit board config;
        src = ./src/logger;
      };

      sharedVaddr = 33554432; # 0x2000000
```

Then replace the body of `mkSystemDescription` and the `pds` attribute:

```nix
        system = microkitTools.mkSystemDescription {
          memoryRegions.shared = {
            size = 4096;
          };

          protectionDomains = {
            logger = {
              priority = 200;
              programImage = logger.programImage;
              maps = [
                {
                  mr = "shared";
                  vaddr = sharedVaddr;
                  perms = "r";
                  setvarVaddr = "shared_vaddr";
                }
              ];
            };

            main = {
              priority = 100;
              programImage = main.programImage;
              maps = [
                {
                  mr = "shared";
                  vaddr = sharedVaddr;
                  perms = "rw";
                  setvarVaddr = "shared_vaddr";
                }
              ];
            };
          };

          channels = [
            {
              ends = [
                {
                  pd = "logger";
                  setvarId = "main_channel";
                }
                {
                  pd = "main";
                  setvarId = "logger_channel";
                }
              ];
            }
          ];
        };

        pds = {
          ${main.programImage} = main;
          ${logger.programImage} = logger;
        };
```

Finally point the check at the new output:

```nix
        if ! grep -qF "logger: hello from a Nix-built seL4 system" console.log; then
```

`nix run` now prints `logger: hello from a Nix-built seL4 system`.

Note the asymmetry in `perms`: `main` maps the page `rw`, `logger` maps it `r`. That restriction is enforced by the kernel's page tables, and the kernel enforcing exactly what the description says is the part of seL4 that has been formally verified.

## Where to go next

- [Microkit manual](https://docs.sel4.systems/projects/microkit/manual/latest/) — every attribute the system description accepts, and the C API
- [seL4 tutorials](https://docs.sel4.systems/Tutorials/) — the kernel underneath
- [nix-sel4](https://github.com/conao3/nix-sel4) — the library this repository consumes, including a two-domain example and the board table
- [LionsOS](https://lionsos.org/) — drivers, a file system and a network stack built out of Microkit components

## License

Apache-2.0.
