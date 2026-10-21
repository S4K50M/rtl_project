typedef unsigned int u32;
#define MMIO(a) (*(volatile u32 *)(a))
static void putc(char c) { MMIO(0x10000000u)=(unsigned char)c; }
static void puts(const char *s) { while(*s) putc(*s++); }
static void hex(u32 v) {
    static const char digits[]="0123456789abcdef";
    for(int i=28;i>=0;i-=4) putc(digits[(v>>i)&15]);
}
int main(void) {
    volatile u32 *scratch=(volatile u32 *)0x3000;
    u32 failures=0;
    puts("RV32 2x2 XY CREDIT NOC\n");
    for(u32 i=0;i<32;i++) scratch[i]=0x12340000u+i;
    for(u32 i=0;i<32;i++) if(scratch[i]!=(0x12340000u+i)) failures++;
    // Exercise byte/halfword stores and signed/unsigned loads through WSTRB.
    *(volatile unsigned char *)scratch=0x80;
    *((volatile unsigned short *)scratch+1)=0xface;
    if(*scratch!=0xface0080u) failures++;
    if(*(volatile signed char *)scratch!=-128) failures++;
    if(*((volatile unsigned short *)scratch+1)!=0xface) failures++;
    puts(failures?"MEMORY FAIL\n":"MEMORY PASS\n");
    u32 t0=MMIO(0x20000000u), t1=MMIO(0x20000000u);
    if(t1<=t0) failures++;
    puts(t1>t0?"TIMER PASS\n":"TIMER FAIL\n");
    // Live traffic on the same request/response meshes used by the CPU.
    MMIO(0x10000020u)=0x80000003u; // hotspot, enable, idle-cycle threshold 1/2
    t0=MMIO(0x20000000u);
    while(MMIO(0x20000000u)-t0<2000) { }
    MMIO(0x10000020u)=0;
    for(u32 i=0;i<16;i++) (void)MMIO(0x20000000u); // drain clients
    u32 injected=MMIO(0x10000024u),delivered=MMIO(0x10000028u);
    if(!injected || injected!=delivered || MMIO(0x10000034u)!=0) failures++;
    puts("live injected=0x"); hex(injected); puts(" delivered=0x"); hex(delivered);
    puts(" mean_Q16=0x"); hex(MMIO(0x1000002cu));
    puts(" variance_Q16=0x"); hex(MMIO(0x10000030u)); putc('\n');
    puts("transactions=0x"); hex(MMIO(0x10000010u));
    puts(" mean_Q16=0x"); hex(MMIO(0x10000014u));
    puts(" variance_Q16=0x"); hex(MMIO(0x10000018u)); putc('\n');
    puts(failures?"SYSTEM FAIL\n":"SYSTEM PASS\n");
    MMIO(0x20000004u)=failures;
    return 0;
}
