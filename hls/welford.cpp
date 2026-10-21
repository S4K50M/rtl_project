#include <cstdint>
// Hand-written HLS source. Exact fixed-point algorithm shared with the RTL
// contract (not an assertion that Vitis generated the supplied RTL).
extern "C" void welford(bool reset, bool valid, uint32_t latency,
                        uint32_t &count, uint32_t &mean_q16, uint32_t &variance_q16) {
    static uint32_t n=0;
    static int64_t mean=0;
    static uint64_t m2=0;
    if(reset) { n=0; mean=0; m2=0; }
    else if(valid && n<65535) {
        int64_t x=int64_t(latency>32767?32767:latency)<<16;
        int64_t delta=x-mean;
        mean+=delta/int64_t(n+1);
        m2+=uint64_t((delta*(x-mean))>>16);
        ++n;
    }
    uint64_t variance=n?m2/n:0;
    count=n; mean_q16=uint32_t(mean);
    variance_q16=variance>0xffffffffULL?0xffffffffU:uint32_t(variance);
}
