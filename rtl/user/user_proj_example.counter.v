// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype none
/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

module user_proj_example #(
    parameter BITS = 32,
	parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11,
    parameter Data_Num    = 600
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);
    wire clk;
    wire rst;

    wire [`MPRJ_IO_PADS-1:0] io_in;
    wire [`MPRJ_IO_PADS-1:0] io_out;
    wire [`MPRJ_IO_PADS-1:0] io_oeb;

    wire [31:0] rdata; 
    //wire [31:0] wdata;
    wire [BITS-1:0] count;

    wire valid;
    wire [3:0] wstrb;
    wire [31:0] la_write;

    // WB MI A
    assign valid = wbs_cyc_i && wbs_stb_i; 
    assign wstrb = wbs_sel_i & {4{wbs_we_i}};
    //assign wdata = wbs_dat_i;

    // IO
    assign io_out = count;
    assign io_oeb = {(`MPRJ_IO_PADS-1){rst}};

    // IRQ
    assign irq = 3'b000;	// Unused

    // LA
    assign la_data_out = {{(127-BITS){1'b0}}, count};
    // Assuming LA probes [63:32] are for controlling the count register  
    assign la_write = ~la_oenb[63:32] & ~{BITS{valid}};
    // Assuming LA probes [65:64] are for controlling the count clk & reset  
    assign clk = (~la_oenb[64]) ? la_data_in[64]: wb_clk_i;
    assign rst = (~la_oenb[65]) ? la_data_in[65]: wb_rst_i;
	wire counter_ack_o;

    counter #(
        .BITS(BITS)
    ) counter(
        .clk(clk),
        .reset(rst),
        .ready(counter_ack_o),
        .valid(valid),
        .rdata(rdata),
        .wdata(wbs_dat_i),
        .wstrb(wstrb),
        .la_write(la_write),
        .la_input(la_data_in[63:32]),
        .count(count)
    );


reg [31:0] reg_mprj_datal;

always @(posedge clk) begin
	if(rst) reg_mprj_datal <= 0;
	else if(wbs_cyc_i && wbs_we_i && (wbs_adr_i == 32'h2600_000c)) begin
		reg_mprj_datal <= wbs_dat_i;
	end else begin
		reg_mprj_datal <= reg_mprj_datal;
	end
end


//1. COEF and ap_start
wire                        		awready;
wire                        		wready;
reg                         		awvalid;
reg   [(pADDR_WIDTH-1): 0]  		awaddr;
reg                         		wvalid;
reg signed [(pDATA_WIDTH-1) : 0] 	wdata;


//2. Xin Write
reg                         		ss_tvalid;
reg signed [(pDATA_WIDTH-1) : 0] 	ss_tdata;
reg                         		ss_tlast;
wire                        		ss_tready;
//3. Yout Read
reg                             	sm_tready;
wire                            	sm_tvalid;
wire signed [(pDATA_WIDTH-1) : 0]   sm_tdata;
wire                            	sm_tlast;

// ram for tap
    wire [3:0]               tap_WE;
    wire                     tap_EN;
    wire [(pDATA_WIDTH-1):0] tap_Di;
    wire [(pADDR_WIDTH-1):0] tap_A;
    wire [(pDATA_WIDTH-1):0] tap_Do;

// ram for data RAM
    wire [3:0]               data_WE;
    wire                     data_EN;
    wire [(pDATA_WIDTH-1):0] data_Di;
    wire [(pADDR_WIDTH-1):0] data_A;
    wire [(pDATA_WIDTH-1):0] data_Do;



//1. COEF and ap_start
//wvalid, awvalid, awaddr, wdata
always @(*) begin
	wvalid = 0;
	awvalid = 0;
	awaddr = 0;
	wdata = 0;
	if((wbs_adr_i == 32'h38000040) && wbs_cyc_i && (wbs_we_i)) begin
		wvalid = 1;
		awvalid = 1;
		awaddr = wbs_adr_i;
		wdata = wbs_dat_i;
	end 
end

//2. Xin 
// ss_tvalid, ss_tdata, ss_tlast
always @(*) begin
	ss_tvalid = 0;
	ss_tdata = 0;
	ss_tlast = 0;
	if((wbs_adr_i == 32'h38000080) && wbs_cyc_i && wbs_we_i) begin
		ss_tvalid = 1;
		ss_tdata = wbs_dat_i;
	end 
	if((wbs_adr_i == 32'h38000088) && wbs_cyc_i && wbs_we_i) begin
		ss_tlast = 1;
	end
end

//3. Yout
// sm_tready
/*
always @(*) begin
	sm_tready = 0;
	if(wbs__cyc_i && (~wbs_we_i) && (wbs_adr_i == 32'h38000084)) begin
		sm_tready = 1;
	end
end
*/

//4. fir_begin_send_x, fir_able_receive_y
//4-1.  fir_able_receive_y <--> sm_tvalid
//		sm_tvalid <--> wbs_ack_o
//4-2.  fir_begin_send_x <--> 
reg fir_begin_send_x_r;//get Xin from firmware
reg fir_able_receive_y_r;//send data to firmware

always @(*) begin
	fir_begin_send_x_r = 0;
	if((wbs_cyc_i) && (wbs_we_i) && (wbs_adr_i == 32'h3000_0004)) begin
		if(ss_tready) fir_begin_send_x_r = 1;
	end
end
//Yout : sm_tready(input for fir)
always @(*) begin
	sm_tready = 0;
	fir_able_receive_y_r = 0;
	if((wbs_cyc_i) && (~wbs_we_i) && (wbs_adr_i == 32'h3000_0004)) begin
		sm_tready = 1;
		if(sm_tvalid) fir_able_receive_y_r = 1;
	end
end

reg [32:0] y_reg;
always @(posedge clk) begin
	if(rst) begin
		y_reg <= 0;
	end else if(sm_tvalid) begin
		y_reg <= sm_tdata;
	end else begin
		y_reg <= y_reg;
	end
end

//5. wbs_dat_o, wbs_ack_o
//Yout, fir_able_receive_y_r, fir_begin_send_x_r
reg [31:0] wbs_dat_o_r;
reg wbs_ack_o_r;
assign wbs_dat_o = wbs_dat_o_r;
assign wbs_ack_o = wbs_ack_o_r;

always @(posedge clk) begin
	if(rst) begin
		wbs_dat_o_r <= 0;
		wbs_ack_o_r <= 0;
	end else if(fir_able_receive_y_r) begin
		wbs_dat_o_r <= 1;
		wbs_ack_o_r <= 1;
	end else if((wbs_cyc_i) && (~wbs_we_i) && (wbs_adr_i == 32'h3000_0084)) begin
		wbs_dat_o_r <= y_reg;
		wbs_ack_o_r <= 1;
	end else if(fir_begin_send_x_r) begin
		wbs_dat_o_r <= 1;
		wbs_ack_o_r <= 1;
	end else if((wbs_cyc_i) && (~wbs_we_i) && (wbs_adr_i == 32'h2600_000c) ) begin
		wbs_dat_o_r <= reg_mprj_datal >> 16;
		wbs_ack_o_r <= 0;
	end else begin
		wbs_dat_o_r <= 0;
		wbs_ack_o_r <= 0;
	end
end


fir fir_DUT(
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),

        .arready(),
        .rready(),
        .arvalid(),
        .araddr(),
        .rvalid(),
        .rdata(),

        .ss_tvalid(ss_tvalid),
        .ss_tdata(ss_tdata),
        .ss_tlast(ss_tlast),
        .ss_tready(ss_tready),

        .sm_tready(sm_tready),
        .sm_tvalid(sm_tvalid),
        .sm_tdata(sm_tdata),
        .sm_tlast(sm_tlast),

        // ram for tap
        .tap_WE(tap_WE),
        .tap_EN(tap_EN),
        .tap_Di(tap_Di),
        .tap_A(tap_A),
        .tap_Do(tap_Do),

        // ram for data
        .data_WE(data_WE),
        .data_EN(data_EN),
        .data_Di(data_Di),
        .data_A(data_A),
        .data_Do(data_Do),

        .axis_clk(clk),
        .axis_rst_n(rst)
);

// RAM for tap
    bram11 tap_RAM (
        .CLK(clk),
        .WE(tap_WE),
        .EN(tap_EN),
        .Di(tap_Di),
        .A(tap_A),
        .Do(tap_Do)
    );

    // RAM for data: choose bram11 or bram12
    bram11 data_RAM(
        .CLK(clk),
        .WE(data_WE),
        .EN(data_EN),
        .Di(data_Di),
        .A(data_A),
        .Do(data_Do)
    );




/*
parameter [3:0] IDLE = 4'd0, SEND_X = 4'd1, DONE = 4'd2; 
reg [3:0] state_ps, state_nx;
always @(posedge clk) begin
	if(rst) begin
		state_ps <= IDLE;
	end else begin
		state_ps <= state_nx;
	end
end
reg send_x_valid_r;
always @(*) begin
	send_x_valid_r = 0;
	case(state_ps)
		IDLE: state_nx = SEND_X;
		SEND_X: begin
			if((wbs_we_i) && (wbs_adr_i == 32'h30000006)) begin
				send_x_valid_r = 1;
				state_nx = DONE;
			end else begin
//				send_x_valid_r = 1;
				state_nx = SEND_X;
			end
		end
		DONE: begin
			state_nx = DONE;
		end
		default: begin
			state_nx = IDLE;
		end
	endcase
end


//assign wbs_dat_o = wbs_ack_o ? 32'h3317 : 0;
//wbs_dat_i, wbs_adr_i
reg [31:0] add_a, add_b;
reg ready_add;
always @(posedge clk) begin
	if(rst) begin
		add_a <= 0;
		add_b <= 0;
		ready_add <= 0;
		send_x_valid_r <= 0;

	end else if((wbs_cyc_i) && (wbs_adr_i == 31'h30000004)) begin
		if(state_ps == SEND_X) begin
			send_x_valid_r <= 1;
		end else begin
			send_x_valid_r <= 0;
		end
	
	end else if((wbs_cyc_i) && (wbs_adr_i == 32'h30000000)) begin
		add_a <= wbs_dat_i;
		add_b <= add_b;
		ready_add <= 0;
	end else if((wbs_cyc_i) && (wbs_adr_i == 32'h30000008)) begin
		add_a <= add_a;
		add_b <= wbs_dat_i;
		ready_add <= 1;
	end else begin
		add_a <= add_a;
		add_b <= add_b;
		ready_add <= 0;
	end
end

reg [31:0] y;
reg valid_send_y;
always @(posedge clk) begin
	if(rst) begin
		y <= 0;
		valid_send_y <= 0;
	end else if(ready_add) begin
		y <= add_a + add_b;
		valid_send_y <= 1;
	end else if((!valid_send_y) & (valid)) begin
		y <= y;
		valid_send_y <= 1;
	end else begin
		y <= y;
		valid_send_y <= 0;
	end
end
reg [31:0] y_reg;
reg valid_send_y_reg;
always @(posedge clk) begin
	if(rst) begin
		y_reg <= 0;
		valid_send_y_reg <= 0;
	end else begin
		y_reg <= y;
		valid_send_y_reg <= valid_send_y;
	end
end

assign wbs_ack_o = send_x_valid_r || valid_send_y_reg ;//|| counter_ack_o;

assign wbs_dat_o = send_x_valid_r ? 1 : (valid_send_y_reg ?  y_reg : (wbs_ack_o ? y_reg : 0));
//assign wbs_ack_o = valid_send_y;
//assign wbs_dat_o = (wbs_ack_o) ? y : 0;

*/

endmodule

//////////////////////////////////
//								//
//			Decoder				//
//								//
//////////////////////////////////
/*
module decoder#(
	parameter ADDR_W = 32
	)(
	input 	i_addr,
	output 	//TODO
);



endmodule
*/
//////////////////////////////////
//								//
//			Counter				//
//								//
//////////////////////////////////

module counter #(
    parameter BITS = 32
)(
    input clk,
    input reset,
    input valid,
    input [3:0] wstrb,
    input [BITS-1:0] wdata,
    input [BITS-1:0] la_write,
    input [BITS-1:0] la_input,
    output ready,
    output [BITS-1:0] rdata,
    output [BITS-1:0] count
);
    reg ready;
    reg [BITS-1:0] count;
    reg [BITS-1:0] rdata;

    always @(posedge clk) begin
        if (reset) begin
            count <= 0;
            ready <= 0;
        end else begin
            ready <= 1'b0;
            if (~|la_write) begin
                count <= count + 1;
            end
            if (valid && !ready) begin
                ready <= 1'b1;
                rdata <= count;
                if (wstrb[0]) count[7:0]   <= wdata[7:0];
                if (wstrb[1]) count[15:8]  <= wdata[15:8];
                if (wstrb[2]) count[23:16] <= wdata[23:16];
                if (wstrb[3]) count[31:24] <= wdata[31:24];
            end else if (|la_write) begin
                count <= la_write & la_input;
            end
        end
    end

endmodule
`default_nettype wire
