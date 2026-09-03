#include <stdint.h>
#include <microkit.h>

/* init runs once, after the kernel has handed this protection domain its
 * capabilities and before any notification can arrive. */
void init(void)
{
    microkit_dbg_puts("main: hello from a Nix-built seL4 system\n");
}

/* notified runs every time another protection domain signals one of this
 * domain's channels. `ch` is the channel identifier from the system
 * description. */
void notified(microkit_channel ch)
{
}
