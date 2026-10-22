/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the software
to the public domain. We make this dedication for the benefit of the
public at large and to the detriment of our heirs and successors.
We intend this dedication to be an overt act of relinquishment in 
perpetuity of all present and future rights to this software under
copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
*/

/**
 * Macros for some common BIOS calls.
 */

#define FREAD 1
#define FWRITE 2
#define FNBLOCK 4
#define FCREATE 0x200

// Call this after writing code to RAM
macro flushCache()                  = bios_a(0x44);

macro initHeap(block, size)         = bios_a(0x39, block, size);
macro malloc(size)                  = bios_a(0x33, size);
macro free(ptr)                     = bios_a(0x34, ptr);
macro exit(code)                    = bios_a(0x06, code);

macro memcpy(dst, src, n)           = bios_a(0x2a, dst, src, n);
macro memset(dst, v, n)             = bios_a(0x2b, dst, v, n);
macro memmove(dst, src, n)          = bios_a(0x2c, dst, src, n);
macro memcmp(a, b, n)               = bios_a(0x2d, a, b, n);
macro strlen(s)                     = bios_a(0x1b, s);
macro strcpy(d, s)                  = bios_a(0x19, d, s);
macro strcmp(a, b)                  = bios_a(0x17, a, b);
macro rand()                        = bios_a(0x2f);
macro srand(seed)                   = bios_a(0x30, seed); // seed is unsigned
macro puts(s)                       = bios_a(0x3e, s);
macro putchar(c)                    = bios_a(0x3c, c);

macro printf(fmt, a1=0, a2=0, a3=0) = bios_a(0x3f, fmt, a1, a2, a3);

macro open(filename, access_mode)   = bios_b(0x32, filename, access_mode);
macro lseek(fd, pos, seektype)      = bios_b(0x33, fd, pos, seektype);
macro read(fd, buf, nbytes)         = bios_b(0x34, fd, buf, nbytes);
macro write(fd, buf, n)             = bios_b(0x35, fd, buf, n);
macro close(fd)                     = bios_b(0x36, fd);
macro firstfile(pattern, entry)     = bios_b(0x42, pattern, entry);
macro nextfile(entry)               = bios_b(0x43, entry);
macro delete(filename)              = bios_b(0x45, filename);
macro rename(f_old, f_new)          = bios_b(0x44, f_old, f_new);

macro cd_init()                     = bios_a(0x54); //_96_init
macro cd_open(filename)             = bios_b(0x32, filename, FREAD);
macro cd_lseek(fd, pos, seektype)   = bios_b(0x33, fd, pos, seektype);
macro cd_read(fd, buf, nbytes)      = bios_b(0x34, fd, buf, nbytes);
macro cd_write(fd, buf, n)          = bios_b(0x35, fd, buf, n);
macro cd_close(fd)                  = bios_b(0x36, fd);
macro cd_firstfile(pattern, entry)  = bios_b(0x42, pattern, entry);
macro cd_nextfile(entry)            = bios_b(0x43, entry);
macro cd_delete(filename)           = bios_b(0x45, filename);
macro cd_rename(f_old, f_new)       = bios_b(0x44, f_old, f_new);

macro event_open(cls, spec, mode, handler) = bios_b(0x08, cls, spec, mode, handler);
macro event_close(ev)               = bios_b(0x09, ev);
macro event_wait(ev)                = bios_b(0x0a, ev);
macro event_test(ev)                = bios_b(0x0b, ev);
macro event_enable(ev)              = bios_b(0x0c, ev);
macro event_disable(ev)             = bios_b(0x0d, ev);
macro event_deliver(cls, spec)      = bios_b(0x07, cls, spec);

macro _bu_init()                    = bios_a(0x70);
macro card_init()                   = bios_b(0x4a, 0);
macro card_start()                  = bios_b(0x4b);
macro card_stop()                   = bios_b(0x4c);

/*
// TODO
macro enqueueIrqHandler(prio, handler) = bios_c(0x02, prio, handler);   // SysEnqIntRP
macro dequeueIrqHandler(prio, handler) = bios_c(0x03, prio, handler);   // SysDeqIntRP
*/

// For code that must not be interrupted by the hardware,
// to protect data shared between the main code and an interrupt handler.
macro enterCriticalSection()        = syscall(0x01);
macro exitCriticalSection()         = syscall(0x02);

#if import

// Structure used in cd_firstfile/cd_nextfile
struct DirEntry
{
    char name[20];
    uint attr;
    uint size;
    uint next_ptr;
    uint lba;
    uint reserved;
};

#endif
