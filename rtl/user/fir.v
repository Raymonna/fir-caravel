`timescale 1ns / 1ps
module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
   
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    
    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);

reg ap_start_reg, ap_idle_reg, ap_done_reg;
parameter IDX_W = 12;

//--------------- AXILITE READ  --------------------//
// 0. output
reg rvalid_r, arready_r;
reg [(pDATA_WIDTH-1):0] rdata_r;
parameter [2:0] AR_IDLE = 0, AR_RADDR = 1, AR_DLEN = 2, AR_AP = 3, AR_COEF = 4, AR_MEMA = 5;//, AR_GETD = 6;

reg [2:0] ar_state_ps, ar_state_nx;
always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		ar_state_ps <= AR_RADDR;	
	end else begin
		ar_state_ps <= ar_state_nx;
	end
end

always @(*) begin
	ar_state_nx = AR_IDLE;
	case(ar_state_ps) 
		AR_IDLE: begin
			ar_state_nx = AR_RADDR;
		end
		AR_RADDR: begin
			if(arvalid) begin
				case(araddr & (8'hf0))
					8'h0: begin//ap_*
						ar_state_nx = AR_AP;
					end
					8'h40: begin//coef
						ar_state_nx = AR_COEF;
					end
					8'h10: begin//data len
						ar_state_nx = AR_DLEN;
					end
				endcase
			end else begin
				ar_state_nx <= AR_RADDR;	
			end
		end
		AR_DLEN: begin
			ar_state_nx = AR_MEMA;
		end
		AR_AP: begin
			ar_state_nx = AR_RADDR;
		end
		AR_COEF: begin
			ar_state_nx = AR_MEMA;
		end
		AR_MEMA: begin//tap_mem addr need one cycle to send
			ar_state_nx = AR_RADDR;
			//if(!arvalid) ar_state_nx = AR_RADDR;
			//else ar_state_nx = AR_GETD;
		end
		/*
		AR_GETD: begin
			ar_state_nx = AR_RADDR;
		end
		*/
	endcase
end
//rvalid, arready, rdata
always @(*) begin
	rvalid_r = 0;
	arready_r = 0;
	rdata_r = 0;
	case(ar_state_ps)
		AR_RADDR: begin
			arready_r = 1;
		end
		AR_DLEN: begin
			arready_r = 1;
		end
		AR_AP: begin
			rvalid_r = 1;
			//rdata_r = 1;
			arready_r = 1;
			rdata_r = {{29{1'b0}}, ap_idle_reg, ap_done_reg, ap_start_reg};	
		end
		AR_COEF: begin
			arready_r = 1;
		end
		AR_MEMA: begin
			rvalid_r = 1;
			case(araddr & (8'hf0))
				8'h0: begin//ap_*
					rdata_r = (data_Do & 32'hf);
				end
				8'h40: begin//coef
					rdata_r = tap_Do;
				end
				8'h10: begin//data len
					rdata_r = (data_Do & 32'hfff0);
				end
			endcase 
		end
		/*
		AR_GETD: begin
			rvalid_r = 1;
			case(araddr_reg & (8'hf0))
				8'h0: begin//ap_*
					rdata_r = (data_Do & 32'hf);
				end
				8'h20: begin//coef
					rdata_r = tap_Do;
				end
				8'h10: begin//data len
					rdata_r = (data_Do & 32'hfff0);
				end
			endcase 
		end
		*/
	endcase
end

//--------------- AXILITE WRITE --------------------//
// In WAIT=> begin ready to receive, go to next state till get the valid signal.

//0. output
reg awready_r, wready_r;

parameter [2:0] AW_IDLE = 0, AW_RADDR = 1, AW_DLEN = 2, AW_AP = 3, AW_COEF = 4;
reg [2:0] aw_state_ps, aw_state_nx;
// 1. update aw_state_ps
always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		aw_state_ps <= AW_IDLE;
	end else begin
		aw_state_ps <= aw_state_nx;
	end
	
end
// 2. update aw_state_nx  3. update data: awready, wready, 
always @(*) begin
	aw_state_nx = AW_RADDR;
	awready_r = 0;
	wready_r = 0;
	case(aw_state_ps)
		AW_IDLE: begin
			aw_state_nx = AW_RADDR;
		end
		AW_RADDR: begin
			aw_state_nx = AW_RADDR;
			awready_r = 1;
			wready_r = 1;
			if(awvalid) begin

				case(awaddr & 8'hf0)
					8'h0: begin//ap
						aw_state_nx = AW_AP;
					end
					8'h10: begin//data_length
						aw_state_nx = AW_DLEN;
					end
					8'h40: begin//coef
						aw_state_nx = AW_COEF;
					end
					default: begin
						aw_state_nx = AW_COEF;
					end
				endcase
			end
		end
		AW_DLEN: begin
			awready_r = 1;
			wready_r = 1;
			aw_state_nx = AW_RADDR;
		end
		AW_AP: begin
			awready_r = 1;
			wready_r = 1;
			aw_state_nx = AW_RADDR;
		end
		AW_COEF: begin
			awready_r = 1;
		 	wready_r = 1;
			aw_state_nx = AW_COEF;
			if(!awvalid) aw_state_nx = AW_RADDR;
		end
	endcase
end	
//------------ Initialize data memory(Xin) ----------//

reg [IDX_W-1:0] init_data_mem_cnt;
reg init_data_mem_EN;
wire [IDX_W-1:0] init_data_mem_cnt_10base;
always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		init_data_mem_cnt <= 1;
		init_data_mem_EN <= 0;
	end else if(init_data_mem_cnt == 12'h800) begin
		init_data_mem_cnt <= init_data_mem_cnt;
		init_data_mem_EN <= 0;
	end else begin//begin from 12'h2
		init_data_mem_cnt <= init_data_mem_cnt << 1;
		init_data_mem_EN <= 1;
	end
end

bcd init_mem_bcd(.i_in(init_data_mem_cnt >> 1), .o_out(init_data_mem_cnt_10base));


//--------------- AXI Stream(ss_*, Xin) -------------//


parameter [4:0] SS_IDLE = 0, SS_RADDR = 1, SS_READX = 2, SS_WAIT = 3, SS_LAST = 4;
reg [4:0] ss_state_ps, ss_state_nx;


always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		ss_state_ps <= SS_IDLE;
	//end else if(!ap_start_r) begin
	//	ss_state_ps <= SS_IDLE;
	end else if (ss_state_ps == SS_IDLE && !ap_start_reg)begin
		ss_state_ps <= SS_IDLE;
	end else 
		ss_state_ps <= ss_state_nx;
end

//count_ss_readx_r
reg [IDX_W-1:0] count_ss_readx_r;

always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		count_ss_readx_r <= 1;
	//end else if(count_ss_readx_r == 12'h800) begin
	//	count_ss_readx_r <= 1;
	//end
	end else if((ss_state_ps == SS_RADDR) && ss_tvalid && (count_ss_readx_r == 12'h800)) begin
		count_ss_readx_r <= 1'b1;
	end else if(ss_state_ps == SS_READX) begin
		count_ss_readx_r <= count_ss_readx_r << 1;
	end else begin
		count_ss_readx_r <= count_ss_readx_r;
	end
end

reg ss_read1x_r, ss_read1x_rr;
always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		ss_read1x_rr <= 0;
	end else begin
		ss_read1x_rr <= ss_read1x_r;
	end
end

reg sm_finish_cal1y_rr, sm_finish_cal1y_r;
always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		sm_finish_cal1y_rr <= 0;
	end else begin
		sm_finish_cal1y_rr <= sm_finish_cal1y_r;
	end
end



//ss_state_nx, sendy_r
reg sm_finish11_r;
reg ss_tready_r;
reg ss_read1x;
always @(*) begin
	ap_idle_reg = 0;
	ss_state_nx = SS_IDLE;
	ss_tready_r = 1;
	ss_read1x = 0;
	ss_read1x_r = 0;
	case(ss_state_ps)
		
		SS_IDLE: begin
			ap_idle_reg = 1;
			ss_tready_r = 0;
			ss_state_nx = SS_RADDR;
		end
		SS_RADDR: begin
			ss_tready_r = 1;//@@
			if(ss_tlast) begin
				ss_state_nx = SS_LAST;
			end else if(ss_tvalid) begin
				ss_state_nx = SS_READX;
			end else begin
				ss_state_nx = SS_RADDR;
			end
		end
		SS_READX: begin
			ss_state_nx = SS_WAIT;
			//if(count_ss_readx_r == 12'h1) ss_state_nx = SS_WAIT;
			//else 				ss_state_nx = SS_RADDR;
		end
		SS_WAIT: begin
			ss_tready_r = 0;
			ss_read1x = 1;
			ss_read1x_r = 1;
			if(sm_finish_cal1y_rr) ss_state_nx = SS_RADDR;
			else ss_state_nx = SS_WAIT;
			
		end
		SS_LAST: begin
			ap_idle_reg = 1;
			ss_state_nx = SS_LAST;
		end
		
	endcase
end


//--------------- AXI Stream(sm_*, Yout) ------------//
parameter [2:0] SM_IDLE = 0, SM_RADDR = 1, SM_CALY = 2, SM_DONE11 = 3; 

reg [2:0] sm_state_ps, sm_state_nx;

reg [IDX_W-1:0] count_sm_mac_r;

always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		count_sm_mac_r <= 1;
	end else if (sm_state_ps == SM_RADDR && (count_sm_mac_r == 12'h800)) begin
		count_sm_mac_r <= 2;
	end else if(sm_state_ps == SM_RADDR && (ss_read1x_rr)) begin
	//end else if(sm_state_ps == SM_RADDR && (count_ss_readx_r > 11'h1)) begin//TODO   and "what to set when equals to 10" //TODO
		count_sm_mac_r <= (count_sm_mac_r << 1);//TODO
	end else begin
		count_sm_mac_r <= count_sm_mac_r;
	end
end

//1. sm_state_ps
always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		sm_state_ps <= SM_IDLE;
	end else begin
		sm_state_ps <= sm_state_nx;
	end
end

reg sm_ready_caly_r;
wire sm_valid_gety;
reg sm_valid_gety_r;
always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		sm_valid_gety_r <= 0;
	end else begin
		sm_valid_gety_r <= sm_valid_gety;
	end
end



reg sm_tvalid_r, sm_tlast_r;
reg [pDATA_WIDTH-1:0] sm_tdata_r;
wire [pDATA_WIDTH-1:0] sm_fir_mac_out;


//2. sm_state_nx, 3. data: sm_tvalid_r, sm_tdata_r, sm_tlast_r//TODO
always @(*) begin
	sm_finish11_r = 0;
	sm_state_nx = SM_IDLE;
	sm_ready_caly_r = 0;
	sm_tvalid_r = 0;
	sm_tdata_r = 0;
	sm_tlast_r = 0;
	sm_finish_cal1y_r = 0;
	case(sm_state_ps)
		SM_IDLE: begin
			sm_state_nx = SM_RADDR;
		end
		SM_RADDR: begin
			if(ss_read1x_rr) begin
			//if(count_ss_readx_r > 12'h1) begin// When ss finish the X0 read 
				sm_state_nx = SM_CALY;
				/*
				if(count_sm_mac_r == 12'h800) begin
					sm_state_nx = SM_DONE11;
					sm_finish11_r = 1;
				end else begin
					//sm_ready_caly_r = 1;
					sm_state_nx = SM_CALY;
				end
				*/
			end else begin
				sm_state_nx = SM_RADDR;
			end
		end
		SM_CALY: begin
			sm_ready_caly_r = 1;
			if (sm_valid_gety_r && sm_tready) begin //TODO  get the desired output and go to the next state
				sm_tdata_r = sm_fir_mac_out;
				sm_tvalid_r = 1;
				//sm_state_nx = SM_RADDR;
				sm_state_nx = SM_DONE11;
				sm_finish_cal1y_r = 1;
			end else begin
				sm_state_nx = SM_CALY;
			end
		
		end
		SM_DONE11: begin
			//$display("\033[35mFIR sm finish 1 yout \033[0m");
			sm_state_nx = SM_RADDR;
		end
	endcase
end


wire sm_data_EN, sm_tap_EN;
wire	[(pADDR_WIDTH-1):0]	sm_data_A, sm_tap_A;
reg 	[pDATA_WIDTH-1:0] 	sm_data_Do_r, sm_tap_Do_r;

always @(*) begin
	sm_data_Do_r = data_Do;
	sm_tap_Do_r = tap_Do;
end

fir_mac_op fir_mac_op(.i_clk(axis_clk), .i_rst_n(axis_rst_n), .i_ready(sm_ready_caly_r), .i_idx(count_sm_mac_r),//if y[0], count_sm_mac_r == 1 
			.o_out(sm_fir_mac_out), .o_valid(sm_valid_gety),
			.data_EN(sm_data_EN), .data_A(sm_data_A), .data_Do(sm_data_Do_r),
			.tap_EN(sm_tap_EN), .tap_A(sm_tap_A), .tap_Do(sm_tap_Do_r));



//---------------  TAP Memory -----------------------//

reg [3:0] tap_WE_r;
reg tap_EN_r;
reg [(pDATA_WIDTH-1):0] tap_Di_r, tap_A_r;


//send arready in RADDR, send araddr in COEF, send EN in MEMA
always @(*) begin
	tap_WE_r = 0;
	tap_EN_r = 0;
	tap_Di_r = 0;
	tap_A_r = 0;
	if(aw_state_ps == AW_COEF) begin
		tap_EN_r = 1;
		tap_WE_r = 4'hf;
		tap_Di_r = wdata;
		tap_A_r = (awaddr & 4'hf) << 2;
	end else if(ar_state_ps == AR_COEF) begin
		tap_EN_r = 0;//1;
		tap_WE_r = 0;
		tap_Di_r = 0;
		tap_A_r = (araddr & 4'hf) << 2;//??
	end else if(ar_state_ps == AR_MEMA) begin
		tap_EN_r = 1;
		tap_WE_r = 0;
		tap_Di_r = 0;
	end else if (sm_ready_caly_r == 1) begin //
		tap_EN_r = sm_tap_EN;
		tap_A_r = sm_tap_A;
	end
end

//------------- DATA Memory(Xin, ap_*) --------------//

reg [3:0] data_WE_r;
reg data_EN_r;
reg [(pDATA_WIDTH-1):0] data_Di_r, data_A_r;



reg ap_start_r;
reg ap_idle_r;
reg ap_done_r;

always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		ap_done_reg <= 0;
	end else if(ss_tlast) begin
		ap_done_reg <= 1;
	end else begin
		ap_done_reg <= ap_done_reg;
	end
end
always @(posedge axis_clk, negedge axis_rst_n) begin
	if(!axis_rst_n) begin
		ap_start_reg <= 0;
	end else if(ss_state_ps > SS_IDLE) begin//RESET after data start to process
		ap_start_reg <= 0;
	end else if(ap_start_r) begin
		ap_start_reg <= ~ap_start_reg;
	end else 
		ap_start_reg <= ap_start_reg;
end

wire [IDX_W-1:0] count_ss_readx_10base;
bcd ss_readx_bcd(.i_in(count_ss_readx_r >> 1), .o_out(count_ss_readx_10base));
always @(*) begin
	data_WE_r = 0;
	data_EN_r = 0;
	data_Di_r = 0;
	data_A_r = 0;
	ap_start_r = 0;
	if(init_data_mem_EN) begin
		data_EN_r = 1;
		data_WE_r = 4'hf;
		data_Di_r = 0;
		data_A_r = (init_data_mem_cnt_10base << 2);
	end else if(aw_state_ps == AW_DLEN) begin
		data_EN_r = 1;
		//data_WE_r = 4'b1110;
		data_Di_r = (wdata << 4);
		data_A_r = 4'd10;
	end else if(aw_state_ps == AW_AP) begin
		data_EN_r = 1;
		//data_WE_r = 4'b0001;
		data_Di_r = wdata;
		data_A_r = 4'd10;
		ap_start_r = 1;
	end else if(ar_state_ps == AR_DLEN) begin
		data_EN_r = 1;
		data_Di_r = 0;
		data_A_r = 4'd10;
	//end else if(ar_state_ps == AR_AP) begin
	//	data_EN_r = 1;
	//	data_A_r = 4'd10;
	end else if(ar_state_ps == AR_MEMA) begin
		data_EN_r = 1;
		data_A_r = 4'd10;
	end else if(ss_state_nx == SS_READX) begin//@@
		data_EN_r = 1;
		data_WE_r = 4'hf;
		data_Di_r = ss_tdata;
		data_A_r = (count_ss_readx_10base) << 2;
	end else if (sm_ready_caly_r == 1) begin //
		data_EN_r = sm_data_EN;
		data_A_r = sm_data_A;
	end
end




// write your code here!
assign awready = awready_r;
assign wready = wready_r;

assign arready = arready_r;
assign rvalid = rvalid_r;
assign rdata = rdata_r;

assign ss_tready = ss_tready_r;
assign sm_tvalid = sm_tvalid_r;
assign sm_tdata = sm_tdata_r;
assign sm_tlast = sm_tlast_r;

assign tap_WE = tap_WE_r;
assign tap_EN = tap_EN_r;
assign tap_Di = tap_Di_r;
assign tap_A = tap_A_r;

assign data_WE = data_WE_r;
assign data_EN = data_EN_r;
assign data_Di = data_Di_r;
assign data_A = data_A_r;


endmodule


//////////////////////////////////////////
//					//
//	     FIR_MAC_OP			//
//					//
//////////////////////////////////////////
//when i_idx == 1, calculate y[0]
//when bcd.i_in == 0010, bcd.o_out == 2
module fir_mac_op#(
	parameter pADDR_WIDTH = 12,
	parameter pDATA_WIDTH = 32,
	parameter IDX_W = 12
	)(
	input 				 i_ready,
	input [IDX_W-1:0] 		 i_idx,
	input 		  		 i_clk,
	input 		  		 i_rst_n,
	
	
	output [(pDATA_WIDTH-1):0] 		 o_out,
	output 				 o_valid,
	
    	output  wire                     data_EN,
    	output  wire [(pADDR_WIDTH-1):0] data_A,
    	input   wire [(pDATA_WIDTH-1):0] data_Do,
    	
	output  wire                     tap_EN,
	output  wire [(pADDR_WIDTH-1):0] tap_A,
	input   wire [(pDATA_WIDTH-1):0] tap_Do				
);
reg data_EN_r, tap_EN_r;
reg [(pADDR_WIDTH-1):0] data_A_r, tap_A_r;
reg [pDATA_WIDTH-1:0] o_out_r_nx, o_out_r_ps;
reg 		      o_valid_r;

assign o_valid = o_valid_r;
assign o_out = o_out_r_ps;
assign data_EN = data_EN_r;
assign data_A = data_A_r;
assign tap_EN = tap_EN_r;
assign tap_A = tap_A_r;


parameter [2:0] IDLE = 3'd0, RADDR = 3'd1, GETD = 3'd2, WAITMEM = 3'd3, SEND_VALID = 3'd4, DONE = 3'd5;

reg [2:0] state_ps, state_nx;

always @(posedge i_clk, negedge i_rst_n) begin
	if(!i_rst_n) begin
		state_ps <= IDLE;
	end else begin
		state_ps <= state_nx;
	end 
end

reg [IDX_W-1:0] count_idx_ps;

always @(posedge i_clk, negedge i_rst_n) begin
	if(!i_rst_n) begin
		count_idx_ps <= i_idx;
	end else if(!i_ready) begin
		count_idx_ps <= i_idx >> 2;
	end else if(state_ps == RADDR && i_ready) begin
		count_idx_ps <= i_idx >> 2;
	//end else if (state_ps == GETD && count_idx_ps == 12'h2) begin
	//	count_idx_ps <= 12'h800;
	end else if (state_ps == GETD) begin
		if(count_idx_ps == 12'h0) count_idx_ps <= 12'h200; 
		else count_idx_ps <= count_idx_ps >> 1;
	end else begin
		count_idx_ps <= count_idx_ps;
	end
end

reg [IDX_W-1:0] x_idx_r;
always @(posedge i_clk, negedge i_rst_n) begin
	if(!i_rst_n) begin
		x_idx_r <= 1;
	end else if(!i_ready) begin
		x_idx_r <= 1;
	end else if(state_ps == RADDR && i_ready) begin
		x_idx_r <= 1;
	end else if(state_ps == GETD) begin
		x_idx_r <= x_idx_r << 1; 
	end else begin
		x_idx_r <= x_idx_r;
	end
end




always @(posedge i_clk, negedge i_rst_n) begin
	if(!i_rst_n) begin
		o_out_r_ps <= 0;
	end else if (state_ps == RADDR) begin
		o_out_r_ps <= 0;
	end else if (state_ps == WAITMEM) begin
		o_out_r_ps <= o_out_r_nx;
	end else begin
		o_out_r_ps <= o_out_r_ps;
	end
end

wire [IDX_W-1:0] count_idx_10base;
bcd fir_bcd(.i_in(count_idx_ps), .o_out(count_idx_10base));// @@ when count_idx_ps == 1, 

wire [IDX_W-1:0] x_idx_10base;
bcd x_bcd(.i_in(x_idx_r >> 1), .o_out(x_idx_10base));

//state_nx, count_idx_nx
//data_A_r, tap_A_r
//data_EN_r, tap_EN_r
//o_out_r_nx
//o_valid_r
always @(*) begin
	state_nx = IDLE;
	o_valid_r = 0;
	o_out_r_nx = 0;
	data_A_r = 0; tap_A_r = 0;
	data_EN_r = 0; tap_EN_r = 0;
	case(state_ps)
		IDLE: begin
			state_nx = RADDR;
		end
		RADDR: begin
			if(i_ready) begin
				state_nx = GETD;
			end else begin
				state_nx = RADDR;
			end
		end
		GETD: begin
			if(x_idx_r != 12'h800) begin
			//if(count_idx_ps != (i_idx >> 1)) begin
			//if((i_idx == 12'h800 && count_idx_ps != 12'h2) 
				//||(i_idx != 12'h800 && count_idx_ps != i_idx)) begin
			//if(count_idx_ps != 1'b1) begin
			 	data_A_r = (x_idx_10base << 2);//TODO
			 	tap_A_r = (count_idx_10base << 2);//TODO
			 	state_nx = WAITMEM;	
			end else begin
				//$display("\033[35mfir_mac_op begin to compute the yout\033[0m");
				state_nx = SEND_VALID;
			end
		end
		WAITMEM: begin
			data_EN_r = 1;
			tap_EN_r = 1;
			o_out_r_nx = o_out_r_ps + data_Do*tap_Do;
			state_nx = GETD;	
		end
		SEND_VALID: begin
		    
		    //$display("\033[32mfir_mac_op finish yout compute \033[0m");
			o_valid_r = 1;
			state_nx = DONE;// NOTICE THAT need to put down the i_ready
		end
		DONE: begin
			state_nx = RADDR;
		end
	endcase
end


endmodule


module bcd#(
	parameter DATA_W = 12	
	)(
	input [DATA_W-1:0]	i_in,
	output [DATA_W-1:0]	o_out
);
reg [DATA_W-1:0] o_out_r;
assign o_out = o_out_r;


integer i;
always @(*) begin
	case(i_in)
		12'b000_0000_0000: o_out_r = 12'd0;
		12'b000_0000_0001: o_out_r = 12'd1;
		12'b000_0000_0010: o_out_r = 12'd2;
		12'b000_0000_0100: o_out_r = 12'd3;
		12'b000_0000_1000: o_out_r = 12'd4;
		
		12'b000_0001_0000: o_out_r = 12'd5;
		12'b000_0010_0000: o_out_r = 12'd6;
		12'b000_0100_0000: o_out_r = 12'd7;
		12'b000_1000_0000: o_out_r = 12'd8;
		12'b001_0000_0000: o_out_r = 12'd9;
		
		12'b010_0000_0000: o_out_r = 12'd10;
		12'b100_0000_0000: o_out_r = 12'd11;
		default: o_out_r = 12'd0;
	endcase
end
endmodule
/*
module bcd_modified#(
    parameter DATA_W = 12
    )(
    input [DATA_W-1:0]  i_in,
    output [DATA_W-1:0] o_out
);
reg [DATA_W-1:0] o_out_r;
assign o_out = o_out_r;


integer i;
always @(*) begin
    case(i_in)
        12'b000_0000_0001: o_out_r = 12'd0;
        12'b000_0000_0010: o_out_r = 12'd1;
        12'b000_0000_0100: o_out_r = 12'd2;
        12'b000_0000_1000: o_out_r = 12'd3;
        12'b000_0001_0000: o_out_r = 12'd4;

        12'b000_0010_0000: o_out_r = 12'd5;
        12'b000_0100_0000: o_out_r = 12'd6;
        12'b000_1000_0000: o_out_r = 12'd7;
        12'b001_0000_0000: o_out_r = 12'd8;
        12'b010_0000_0000: o_out_r = 12'd9;

        12'b100_0000_0000: o_out_r = 12'd10;
        12'b1000_0000_0000: o_out_r = 12'd11;
        default: o_out_r = 12'd0;
    endcase
end

endmodule
*/
