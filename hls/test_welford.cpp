#include <cassert>
#include <cstdint>
#include <iostream>
extern "C" void welford(bool,bool,uint32_t,uint32_t&,uint32_t&,uint32_t&);
int main(){
    uint32_t n,m,v; welford(true,false,0,n,m,v);
    for(uint32_t x: {2,4,4,4,5,5,7,9}) welford(false,true,x,n,m,v);
    assert(n==8 && m>327670 && m<327690 && v>262130 && v<262160);
    std::cout<<"HLS Welford PASS n="<<n<<" mean="<<m<<" variance="<<v<<"\n";
    welford(true,false,0,n,m,v);
    for(unsigned i=0;i<65540;i++) welford(false,true,40000,n,m,v);
    assert(n==65535 && m==(32767U<<16) && v==0);
    std::cout<<"HLS saturation/clamp PASS\n";
}
