module bios;

import std.array : split;
import std.format : format;

/**
 * PSX BIOS function names, called via the A0h / B0h / C0h dispatchers
 * (table address in $t2, function number in $t1).
 *
 * The tables are partial: unknown numbers are printed without a name.
 */

private string[uint] a0, b0, c0;

private void fill(ref string[uint] tbl, uint start, string names)
{
    foreach (i, n; names.split)
        tbl[start + cast(uint)i] = n;
}

static this()
{
    // A(00h)..A(4Eh)
    fill(a0, 0x00,
        "FileOpen FileSeek FileRead FileWrite FileClose FileIoctl exit " ~
        "FileGetDeviceFlag FileGetc FilePutc todigit atof strtoul strtol " ~
        "abs labs atoi atol atob SaveState RestoreState strcat strncat " ~
        "strcmp strncmp strcpy strncpy strlen index rindex strchr strrchr " ~
        "strpbrk strspn strcspn strtok strstr toupper tolower bcopy bzero " ~
        "bcmp memcpy memset memmove memcmp memchr rand srand qsort strtod " ~
        "malloc free lsearch bsearch calloc realloc InitHeap SystemErrorExit " ~
        "std_in_getchar std_out_putchar std_in_gets std_out_puts printf " ~
        "SystemErrorUnresolvedException LoadExeHeader LoadExeFile DoExecute " ~
        "FlushCache init_a0_b0_c0_vectors GPU_dw gpu_send_dma SendGP1Command " ~
        "GPU_cw GPU_cwp send_gpu_linked_list gpu_abort_dma GetGPUStatus gpu_sync");
    a0[0x51] = "LoadAndExecute";
    a0[0x70] = "_bu_init";
    a0[0x71] = "CdInit";
    a0[0x72] = "CdRemove";
    
    // B(00h)..B(19h)
    fill(b0, 0x00,
        "alloc_kernel_memory free_kernel_memory init_timer get_timer " ~
        "enable_timer_irq disable_timer_irq restart_timer DeliverEvent " ~
        "OpenEvent CloseEvent WaitEvent TestEvent EnableEvent DisableEvent " ~
        "OpenThread CloseThread ChangeThread jump_to_00000000h InitPad " ~
        "StartPad StopPad OutdatedPadInitAndStart OutdatedPadGetButtons " ~
        "ReturnFromException SetDefaultExitFromException " ~
        "SetCustomExitFromException");
    b0[0x20] = "UnDeliverEvent";
    // B(32h)..B(50h)
    fill(b0, 0x32,
        "FileOpen FileSeek FileRead FileWrite FileClose FileIoctl exit " ~
        "FileGetDeviceFlag FileGetc FilePutc std_in_getchar std_out_putchar " ~
        "std_in_gets std_out_puts chdir FormatDevice firstfile nextfile " ~
        "FileRename FileDelete FileUndelete AddDevice RemoveDevice " ~
        "PrintInstalledDevices InitCard StartCard StopCard _card_info_subfunc " ~
        "write_card_sector read_card_sector allow_new_card");
    fill(b0, 0x56, "GetC0Table GetB0Table get_bu_callback_port testdevice");
    b0[0x5b] = "ChangeClearPad";
    
    // C(00h)..C(0Ah)
    fill(c0, 0x00,
        "EnqueueTimerAndVblankIrqs EnqueueSyscallHandler SysEnqIntRP " ~
        "SysDeqIntRP get_free_EvCB_slot get_free_TCB_slot ExceptionHandler " ~
        "InstallExceptionHandlers SysInitMemory SysInitKernelVariables " ~
        "ChangeClearRCnt");
    c0[0x0c] = "InitDefInt";
    c0[0x0d] = "SetIrqAutoAck";
    c0[0x12] = "InstallDevices";
    c0[0x13] = "FlushStdInOutPut";
    fill(c0, 0x15, "tty_cdevinput tty_cdevscan tty_circgetc tty_circputc " ~
                   "ioabort set_card_find_mode KernelRedirect AdjustA0Table " ~
                   "get_card_find_mode");
}

/// table: 0xA0, 0xB0 or 0xC0. func: function number, or -1 if unknown.
string biosCall(uint table, int func)
{
    char letter = table == 0xa0 ? 'A' : (table == 0xb0 ? 'B' : 'C');
    
    if (func < 0)
        return format("BIOS %s(?)", letter);
    
    uint f = cast(uint)func;
    string* p;
    if (table == 0xa0)
        p = f in a0;
    else if (table == 0xb0)
        p = f in b0;
    else
        p = f in c0;
    
    if (p is null)
        return format("BIOS %s(0x%02X)", letter, f);
    return format("BIOS %s(0x%02X) %s", letter, f, *p);
}
