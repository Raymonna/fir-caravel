//#include "fir.h"
//#include <defs.h>
//#include <stub.c>

//#define reg_mprj_slave (*(volatile uint32_t *) 0x30000000)
//#define reg_mprj_slave2 (*(volatile uint32_t *) 0x30000004)



void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	/*
	reg_mprj_slave = 0x1234;//0x00002710;
    reg_mprj_slave2 = 0x0112;
    //reg_mprj_datal = 0xAB610000;
    if (reg_mprj_slave == 0x1346){//0x3317) {
        reg_mprj_datal = 0xAB610000;
    }
    reg_mprj_slave = 0x221;
    reg_mprj_slave2 = 0x312;
    if(reg_mprj_slave == 0x533){
        reg_mprj_datal = 0xAB620000;
	}
*/
//	return outputsignal;
}
		
